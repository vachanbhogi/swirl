// Prevents an additional console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod jac_runtime;
mod macos;
mod mcp;
mod models;
mod storage;
mod triggers;

use macos::{MacActionRequest, MacActionResult};
use mcp::{McpManager, McpServerConfig, McpState};
use models::{
    ExecutionEvent, ExecutionSummary, WorkflowDocument, WorkflowExecutionRequest, WorkflowNode,
};
use serde_json::{json, Map, Value};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
};
use tauri::{AppHandle, Emitter, Manager, State};

const WORKFLOW_EVENT: &str = "swirl-workflow-event";
static RUN_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Default)]
struct WorkflowRunState(Mutex<HashMap<String, Arc<AtomicBool>>>);

fn emit(app: &AppHandle, event: ExecutionEvent) {
    let _ = app.emit(WORKFLOW_EVENT, event);
}

fn event(
    event: &str,
    node: Option<&WorkflowNode>,
    status: Option<&str>,
    message: Option<String>,
    output: Option<Value>,
) -> ExecutionEvent {
    ExecutionEvent {
        event: event.into(),
        run_id: None,
        iteration: None,
        node_id: node.map(|value| value.id.clone()),
        title: node.map(|value| value.title.clone()),
        status: status.map(str::to_string),
        message,
        output,
    }
}

fn run_event(
    event_name: &str,
    run_id: &str,
    iteration: u64,
    node: Option<&WorkflowNode>,
    status: Option<&str>,
    message: Option<String>,
    output: Option<Value>,
) -> ExecutionEvent {
    let mut value = event(event_name, node, status, message, output);
    value.run_id = Some(run_id.to_string());
    value.iteration = Some(iteration);
    value
}

fn context_object(value: Value) -> Map<String, Value> {
    value.as_object().cloned().unwrap_or_default()
}

fn mcp_arguments(app: &AppHandle, node: &WorkflowNode, context: &Map<String, Value>) -> Value {
    let mut arguments = node
        .config
        .get("params")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let context_text = context
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default();
    match node.block_type.as_str() {
        "mcp_fetch" => {
            arguments.entry("url").or_insert_with(|| {
                node.config
                    .get("url")
                    .cloned()
                    .unwrap_or_else(|| Value::String(context_text.into()))
            });
        }
        "mcp_fs" => {
            let configured_path = node
                .config
                .get("path")
                .and_then(Value::as_str)
                .unwrap_or("$SWIRL_DOCUMENTS");
            let documents = app
                .path()
                .document_dir()
                .ok()
                .map(|path| path.to_string_lossy().to_string())
                .unwrap_or_else(|| ".".into());
            arguments.entry("path").or_insert_with(|| {
                Value::String(configured_path.replace("$SWIRL_DOCUMENTS", &documents))
            });
        }
        "mcp_search" => {
            arguments.entry("query").or_insert_with(|| {
                node.config
                    .get("query")
                    .cloned()
                    .unwrap_or_else(|| Value::String(context_text.into()))
            });
            arguments.entry("count").or_insert_with(|| {
                node.config
                    .get("maxResults")
                    .cloned()
                    .unwrap_or_else(|| Value::Number(5.into()))
            });
        }
        _ => {}
    }
    Value::Object(arguments)
}

fn mcp_result_text(result: &Value) -> Option<String> {
    let text = result
        .get("content")?
        .as_array()?
        .iter()
        .filter_map(|item| item.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("\n");
    (!text.is_empty()).then_some(text)
}

fn local_email_summary(input: &str, email: Option<&Value>) -> (String, Vec<String>) {
    let compact = input.split_whitespace().collect::<Vec<_>>().join(" ");
    let sentences = compact
        .split_inclusive(['.', '!', '?'])
        .map(str::trim)
        .filter(|sentence| !sentence.is_empty())
        .collect::<Vec<_>>();
    let mut summary_body = sentences
        .iter()
        .take(3)
        .copied()
        .collect::<Vec<_>>()
        .join(" ");
    if summary_body.is_empty() {
        summary_body = compact.chars().take(700).collect();
    }
    if summary_body.chars().count() > 700 {
        summary_body = summary_body.chars().take(700).collect::<String>() + "…";
    }

    let action_words = [
        "please",
        "need to",
        "must",
        "action",
        "due",
        "deadline",
        "required",
        "can you",
        "could you",
        "follow up",
        "reply",
    ];
    let action_items = sentences
        .iter()
        .filter(|sentence| {
            let lowered = sentence.to_ascii_lowercase();
            action_words.iter().any(|word| lowered.contains(word))
        })
        .take(5)
        .map(|sentence| sentence.trim().to_string())
        .collect::<Vec<_>>();

    let mut formatted = if let Some(email) = email {
        let subject = email
            .get("subject")
            .and_then(Value::as_str)
            .unwrap_or("No subject");
        let sender = email
            .get("sender")
            .and_then(Value::as_str)
            .unwrap_or("Unknown sender");
        format!("From: {sender}\nSubject: {subject}\n\nSummary:\n{summary_body}")
    } else {
        format!("Summary:\n{summary_body}")
    };
    if !action_items.is_empty() {
        formatted.push_str("\n\nAction items:\n");
        formatted.push_str(
            &action_items
                .iter()
                .map(|item| format!("• {item}"))
                .collect::<Vec<_>>()
                .join("\n"),
        );
    }
    (formatted, action_items)
}

fn execute_node(
    app: &AppHandle,
    node: &WorkflowNode,
    context: &mut Map<String, Value>,
    approved: bool,
    mcp: &State<'_, McpState>,
) -> Result<Value, MacActionResult> {
    match node.category.as_str() {
        "source" => {
            let output = json!({
                "status": "started",
                "triggerType": "manual",
                "timestampMs": std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|duration| duration.as_millis())
                    .unwrap_or(0),
                "payload": node.config
            });
            context.insert("trigger".into(), output.clone());
            context.insert("triggerType".into(), Value::String("manual".into()));
            Ok(output)
        }
        "ai" => {
            let input = context
                .get("text")
                .and_then(Value::as_str)
                .or_else(|| node.config.get("text").and_then(Value::as_str))
                .unwrap_or_default();
            let instruction = (!node.custom_prompt.trim().is_empty())
                .then_some(node.custom_prompt.as_str())
                .or_else(|| node.config.get("prompt").and_then(Value::as_str))
                .unwrap_or("Summarize concisely");
            let llm_configured = jac_runtime::runtime_script(app)
                .map(|script| jac_runtime::nvidia_api_key_configured(&script))
                .unwrap_or(false);
            let llm_result = llm_configured
                .then(|| {
                    jac_runtime::invoke(
                        app,
                        "llm-transform",
                        &json!({ "text": input, "instruction": instruction }),
                    )
                })
                .transpose();
            let (local_summary, local_action_items) =
                local_email_summary(input, context.get("email"));
            let (summary, mode, fallback_error) = match llm_result {
                Ok(Some(value)) => {
                    let generated = value
                        .get("text")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .trim()
                        .to_string();
                    if generated.is_empty() {
                        (local_summary.clone(), "local-extractive", Value::Null)
                    } else {
                        (generated, "by-llm", Value::Null)
                    }
                }
                Ok(None) => (local_summary.clone(), "local-extractive", Value::Null),
                Err(error) => (
                    local_summary.clone(),
                    "local-extractive",
                    Value::String(error),
                ),
            };
            let output = json!({
                "summary": summary,
                "actionItems": local_action_items,
                "engine": "Jac LLMTransformBlock",
                "mode": mode,
                "fallbackError": fallback_error
            });
            context.insert(
                "text".into(),
                output.get("summary").cloned().unwrap_or(Value::Null),
            );
            Ok(output)
        }
        "mac" => {
            let mut params = node.config.clone();
            if let Some(object) = params.as_object_mut() {
                if node.block_type == "mac_notes" && !object.contains_key("title") {
                    if let Some(subject) = context
                        .get("email")
                        .and_then(|email| email.get("subject"))
                        .and_then(Value::as_str)
                    {
                        object.insert(
                            "title".into(),
                            Value::String(format!("Email Summary — {subject}")),
                        );
                    }
                }
                if !object.contains_key("content") {
                    if let Some(text) = context.get("text") {
                        object.insert("content".into(), text.clone());
                    }
                }
                if !object.contains_key("text") {
                    if let Some(text) = context.get("text") {
                        object.insert("text".into(), text.clone());
                    }
                }
            }
            let request = MacActionRequest {
                app: node
                    .config
                    .get("app")
                    .and_then(Value::as_str)
                    .unwrap_or_else(|| {
                        if node.block_type.contains("finder") {
                            "Finder"
                        } else {
                            "System"
                        }
                    })
                    .to_string(),
                action: node
                    .config
                    .get("action")
                    .and_then(Value::as_str)
                    .unwrap_or("display_notification")
                    .to_string(),
                params,
                approved,
            };
            let result = macos::execute(&request);
            if result.success {
                if node.block_type == "mac_wait_email" {
                    let email = result.output.clone().unwrap_or(Value::Null);
                    context.insert("email".into(), email.clone());
                    context.insert(
                        "text".into(),
                        email.get("content").cloned().unwrap_or(Value::Null),
                    );
                }
                Ok(serde_json::to_value(result).unwrap_or(Value::Null))
            } else {
                Err(result)
            }
        }
        "mcp" => {
            let server = node
                .config
                .get("server")
                .and_then(Value::as_str)
                .unwrap_or("");
            let tool = node
                .config
                .get("tool_name")
                .and_then(Value::as_str)
                .unwrap_or("");
            let arguments = mcp_arguments(app, node, context);
            let result = mcp
                .0
                .lock()
                .map_err(|error| MacActionResult {
                    success: false,
                    output: None,
                    error: Some(error.to_string()),
                    approval_required: false,
                    risk: "low".into(),
                })?
                .call(server, tool, arguments)
                .map_err(|error| MacActionResult {
                    success: false,
                    output: None,
                    error: Some(error),
                    approval_required: false,
                    risk: "low".into(),
                })?;
            if let Some(text) = mcp_result_text(&result) {
                context.insert("text".into(), Value::String(text));
            }
            Ok(result)
        }
        "logic" => {
            let value = context
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let expected = node
                .config
                .get("matchString")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let operator = node
                .config
                .get("operator")
                .and_then(Value::as_str)
                .unwrap_or("contains");
            let matched = match operator {
                "equals" => value == expected,
                "not_contains" => !value.contains(expected),
                _ => value.contains(expected),
            };
            context.insert("condition".into(), Value::Bool(matched));
            Ok(json!({ "matched": matched, "operator": operator, "expected": expected }))
        }
        "output" => {
            let webhook = node
                .config
                .get("webhookUrl")
                .and_then(Value::as_str)
                .unwrap_or("");
            if webhook.starts_with("https://") && !webhook.contains("MOCK") {
                if !approved {
                    return Err(MacActionResult {
                        success: false,
                        output: None,
                        error: Some(
                            "Approval is required before posting to an external webhook".into(),
                        ),
                        approval_required: true,
                        risk: "medium".into(),
                    });
                }
                let payload = json!({
                    "text": context.get("text").and_then(Value::as_str).unwrap_or("Swirl workflow completed")
                });
                let response = reqwest::blocking::Client::new()
                    .post(webhook)
                    .json(&payload)
                    .send()
                    .map_err(|error| MacActionResult {
                        success: false,
                        output: None,
                        error: Some(error.to_string()),
                        approval_required: false,
                        risk: "medium".into(),
                    })?;
                Ok(json!({ "status": response.status().as_u16() }))
            } else {
                Ok(json!({ "status": "skipped", "reason": "No configured production webhook" }))
            }
        }
        _ => Ok(json!({ "status": "executed", "config": node.config })),
    }
}

#[tauri::command]
fn backend_health(app: AppHandle) -> Value {
    jac_runtime::health(&app)
}

fn validate_generated_catalog(workflow: &WorkflowDocument) -> Result<(), String> {
    const SOURCE_EVENTS: &[&str] = &[
        "trigger_email",
        "trigger_file",
        "trigger_cron",
        "trigger_clipboard",
        "trigger_webhook",
        "trigger_voice",
    ];
    const BLOCKS: &[(&str, &str)] = &[
        ("llm_summarize", "ai"),
        ("llm_extract", "ai"),
        ("llm_classifier", "ai"),
        ("mac_notes", "mac"),
        ("mac_finder", "mac"),
        ("mac_notification", "mac"),
        ("mac_terminal", "mac"),
        ("mcp_fetch", "mcp"),
        ("mcp_fs", "mcp"),
        ("mcp_search", "mcp"),
        ("logic_if", "logic"),
        ("output_slack", "output"),
    ];
    for node in &workflow.nodes {
        if node.category == "source" {
            let event_type = node
                .config
                .get("eventType")
                .and_then(Value::as_str)
                .ok_or_else(|| "Generated Source is missing eventType".to_string())?;
            if node.block_type != "source" || !SOURCE_EVENTS.contains(&event_type) {
                return Err(format!("Unsupported generated Source event: {event_type}"));
            }
            let run_mode = node
                .config
                .get("runMode")
                .and_then(Value::as_str)
                .unwrap_or("once");
            if !matches!(run_mode, "once" | "continuous") {
                return Err(format!("Unsupported generated Source run mode: {run_mode}"));
            }
        } else if !BLOCKS.contains(&(node.block_type.as_str(), node.category.as_str())) {
            return Err(format!(
                "Unsupported generated block/category pair: {}/{}",
                node.block_type, node.category
            ));
        }
    }
    Ok(())
}

#[tauri::command]
fn compile_prompt(app: AppHandle, prompt: String, use_llm: Option<bool>) -> Result<Value, String> {
    let generated = jac_runtime::invoke(
        &app,
        if use_llm.unwrap_or(false) {
            "prompt-llm"
        } else {
            "prompt"
        },
        &json!({ "prompt": prompt }),
    )?;
    let workflow: WorkflowDocument = serde_json::from_value(generated.clone())
        .map_err(|error| format!("Jac LLM returned a malformed workflow: {error}"))?;
    workflow.validate()?;
    validate_generated_catalog(&workflow)?;
    Ok(generated)
}

#[tauri::command]
fn generate_jac_source(app: AppHandle, workflow: WorkflowDocument) -> Result<String, String> {
    workflow.validate()?;
    let value = serde_json::to_value(workflow).map_err(|error| error.to_string())?;
    jac_runtime::invoke(&app, "code", &value)?
        .get("source")
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| "Jac code generator returned no source".into())
}

#[tauri::command]
fn execute_workflow(
    app: AppHandle,
    request: WorkflowExecutionRequest,
    mcp: State<'_, McpState>,
) -> Result<ExecutionSummary, String> {
    request.workflow.validate()?;
    let workflow_value =
        serde_json::to_value(&request.workflow).map_err(|error| error.to_string())?;
    let plan_value = jac_runtime::invoke(&app, "plan", &workflow_value)?;
    let planned_nodes: Vec<WorkflowNode> = serde_json::from_value(
        plan_value
            .get("plan")
            .cloned()
            .ok_or_else(|| "Jac planner returned no execution plan".to_string())?,
    )
    .map_err(|error| format!("Invalid Jac execution plan: {error}"))?;

    println!(
        "[Swirl][Workflow] running {} planned node(s)",
        planned_nodes.len()
    );

    emit(
        &app,
        event(
            "start",
            None,
            Some("running"),
            Some("WorkflowExecutorWalker started graph traversal".into()),
            None,
        ),
    );

    let mut context = context_object(request.context);
    let mut results = HashMap::new();
    let mut completed = Vec::new();
    let mut failed_node_id = None;

    for node in &planned_nodes {
        println!(
            "[Swirl][Workflow] starting node '{}' ({})",
            node.title, node.category
        );
        context.insert(
            "customPrompt".into(),
            Value::String(node.custom_prompt.clone()),
        );
        context.insert("currentNodeId".into(), Value::String(node.id.clone()));
        emit(
            &app,
            event(
                "node_start",
                Some(node),
                Some("running"),
                (!node.custom_prompt.trim().is_empty())
                    .then(|| "Custom prompt added to execution context".into()),
                None,
            ),
        );
        match execute_node(
            &app,
            node,
            &mut context,
            request.approvals.contains(&node.id),
            &mcp,
        ) {
            Ok(output) => {
                let output = match output {
                    Value::Object(mut object) => {
                        object.insert(
                            "customPrompt".into(),
                            Value::String(node.custom_prompt.clone()),
                        );
                        Value::Object(object)
                    }
                    value => json!({ "result": value, "customPrompt": node.custom_prompt }),
                };
                println!("[Swirl][Workflow] completed node '{}'", node.title);
                context.insert(format!("node:{}", node.id), output.clone());
                results.insert(node.id.clone(), output.clone());
                completed.push(node.id.clone());
                emit(
                    &app,
                    event(
                        "node_complete",
                        Some(node),
                        Some("success"),
                        None,
                        Some(output),
                    ),
                );
            }
            Err(error) => {
                eprintln!(
                    "[Swirl][Workflow] node '{}' stopped: {}",
                    node.title,
                    error.error.as_deref().unwrap_or("unknown error")
                );
                failed_node_id = Some(node.id.clone());
                let output = serde_json::to_value(&error).unwrap_or(Value::Null);
                let event_name = if error.approval_required {
                    "approval_required"
                } else {
                    "node_error"
                };
                emit(
                    &app,
                    event(
                        event_name,
                        Some(node),
                        Some("error"),
                        error.error.clone(),
                        Some(output.clone()),
                    ),
                );
                results.insert(node.id.clone(), output);
                break;
            }
        }
    }

    let success = failed_node_id.is_none();
    println!(
        "[Swirl][Workflow] {}",
        if success {
            "completed successfully"
        } else {
            "stopped with an error"
        }
    );
    let summary = ExecutionSummary {
        success,
        context: Value::Object(context),
        results,
        completed_node_ids: completed,
        failed_node_id,
    };
    emit(
        &app,
        event(
            if success { "complete" } else { "failed" },
            None,
            Some(if success { "success" } else { "error" }),
            Some(if success {
                "Workflow graph traversal completed".into()
            } else {
                "Workflow paused or failed".into()
            }),
            Some(serde_json::to_value(&summary).unwrap_or(Value::Null)),
        ),
    );
    let _ = storage::save_trace(&app, &serde_json::to_value(&summary).unwrap_or(Value::Null));
    Ok(summary)
}

#[tauri::command]
fn start_workflow(
    app: AppHandle,
    request: WorkflowExecutionRequest,
    runs: State<'_, WorkflowRunState>,
) -> Result<Value, String> {
    request.workflow.validate()?;
    let workflow_value =
        serde_json::to_value(&request.workflow).map_err(|error| error.to_string())?;
    let plan_value = jac_runtime::invoke(&app, "plan", &workflow_value)?;
    let planned_nodes: Vec<WorkflowNode> = serde_json::from_value(
        plan_value
            .get("plan")
            .cloned()
            .ok_or_else(|| "Jac planner returned no execution plan".to_string())?,
    )
    .map_err(|error| format!("Invalid Jac execution plan: {error}"))?;
    let source = planned_nodes
        .first()
        .filter(|node| node.category == "source")
        .ok_or_else(|| "Jac execution plan must begin with Source".to_string())?;
    let run_mode = source
        .config
        .get("runMode")
        .and_then(Value::as_str)
        .unwrap_or("once")
        .to_string();
    if !matches!(run_mode.as_str(), "once" | "continuous") {
        return Err("Source runMode must be once or continuous".into());
    }

    let run_id = format!(
        "run-{}-{}",
        std::process::id(),
        RUN_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let cancelled = Arc::new(AtomicBool::new(false));
    runs.0
        .lock()
        .map_err(|error| error.to_string())?
        .insert(run_id.clone(), cancelled.clone());

    let thread_app = app.clone();
    let thread_run_id = run_id.clone();
    let thread_run_mode = run_mode.clone();
    std::thread::spawn(move || {
        println!(
            "[Swirl][Workflow][{}] started in {} mode ({} planned nodes)",
            thread_run_id,
            thread_run_mode,
            planned_nodes.len()
        );
        let source = planned_nodes.first().expect("Source checked before spawn");
        let mut iteration = 1_u64;
        let mut terminal_event = "stopped";
        loop {
            if cancelled.load(Ordering::Relaxed) {
                break;
            }
            println!(
                "[Swirl][Workflow][{}] arming '{}' for iteration {}",
                thread_run_id, source.title, iteration
            );
            emit(
                &thread_app,
                run_event(
                    "armed",
                    &thread_run_id,
                    iteration,
                    Some(source),
                    Some("running"),
                    Some(format!(
                        "Waiting for {}",
                        source
                            .config
                            .get("eventType")
                            .and_then(Value::as_str)
                            .unwrap_or("source event")
                    )),
                    None,
                ),
            );

            let source_event = match triggers::wait_for_source(source, &cancelled) {
                Ok(Some(value)) => value,
                Ok(None) => break,
                Err(error) => {
                    terminal_event = "failed";
                    eprintln!(
                        "[Swirl][Workflow][{}] Source failed: {}",
                        thread_run_id, error
                    );
                    emit(
                        &thread_app,
                        run_event(
                            "failed",
                            &thread_run_id,
                            iteration,
                            Some(source),
                            Some("error"),
                            Some(error),
                            None,
                        ),
                    );
                    break;
                }
            };
            let source_output = source_event.output();
            println!(
                "[Swirl][Workflow][{}] Source triggered: {}",
                thread_run_id, source_event.trigger_type
            );
            emit(
                &thread_app,
                run_event(
                    "triggered",
                    &thread_run_id,
                    iteration,
                    Some(source),
                    Some("success"),
                    Some(format!("{} received", source_event.trigger_type)),
                    Some(source_output.clone()),
                ),
            );

            let mut context = context_object(request.context.clone());
            context.insert("trigger".into(), source_output.clone());
            context.insert(
                "triggerType".into(),
                Value::String(source_event.trigger_type.clone()),
            );
            context.insert(
                "triggerTimestamp".into(),
                Value::Number(source_event.timestamp_ms.into()),
            );
            context.insert("payload".into(), source_event.payload.clone());
            context.insert("text".into(), Value::String(source_event.text.clone()));
            if source_event.trigger_type == "trigger_email" {
                context.insert("email".into(), source_event.payload.clone());
            }

            let mut results = HashMap::from([(source.id.clone(), source_output)]);
            let mut completed = vec![source.id.clone()];
            let mut failed_node_id = None;
            for node in planned_nodes.iter().skip(1) {
                if cancelled.load(Ordering::Relaxed) {
                    break;
                }
                println!(
                    "[Swirl][Workflow][{}] starting node '{}' ({})",
                    thread_run_id, node.title, node.category
                );
                emit(
                    &thread_app,
                    run_event(
                        "node_start",
                        &thread_run_id,
                        iteration,
                        Some(node),
                        Some("running"),
                        None,
                        None,
                    ),
                );
                let mcp = thread_app.state::<McpState>();
                match execute_node(
                    &thread_app,
                    node,
                    &mut context,
                    request.approvals.contains(&node.id),
                    &mcp,
                ) {
                    Ok(output) => {
                        println!(
                            "[Swirl][Workflow][{}] completed node '{}'",
                            thread_run_id, node.title
                        );
                        context.insert(format!("node:{}", node.id), output.clone());
                        results.insert(node.id.clone(), output.clone());
                        completed.push(node.id.clone());
                        emit(
                            &thread_app,
                            run_event(
                                "node_complete",
                                &thread_run_id,
                                iteration,
                                Some(node),
                                Some("success"),
                                None,
                                Some(output),
                            ),
                        );
                    }
                    Err(error) => {
                        terminal_event = "failed";
                        failed_node_id = Some(node.id.clone());
                        let output = serde_json::to_value(&error).unwrap_or(Value::Null);
                        emit(
                            &thread_app,
                            run_event(
                                if error.approval_required {
                                    "approval_required"
                                } else {
                                    "node_error"
                                },
                                &thread_run_id,
                                iteration,
                                Some(node),
                                Some("error"),
                                error.error.clone(),
                                Some(output.clone()),
                            ),
                        );
                        results.insert(node.id.clone(), output);
                        break;
                    }
                }
            }

            if cancelled.load(Ordering::Relaxed) {
                break;
            }
            let success = failed_node_id.is_none();
            let summary = ExecutionSummary {
                success,
                context: Value::Object(context),
                results,
                completed_node_ids: completed,
                failed_node_id,
            };
            let summary_value = serde_json::to_value(&summary).unwrap_or(Value::Null);
            let _ = storage::save_trace(&thread_app, &summary_value);
            if !success {
                emit(
                    &thread_app,
                    run_event(
                        "failed",
                        &thread_run_id,
                        iteration,
                        None,
                        Some("error"),
                        Some("Workflow stopped after a node failure".into()),
                        Some(summary_value),
                    ),
                );
                break;
            }
            if thread_run_mode == "once" {
                terminal_event = "complete";
                emit(
                    &thread_app,
                    run_event(
                        "complete",
                        &thread_run_id,
                        iteration,
                        None,
                        Some("success"),
                        Some("Workflow completed".into()),
                        Some(summary_value),
                    ),
                );
                break;
            }
            emit(
                &thread_app,
                run_event(
                    "iteration_complete",
                    &thread_run_id,
                    iteration,
                    None,
                    Some("success"),
                    Some(format!("Iteration {iteration} completed; Source re-armed")),
                    Some(summary_value),
                ),
            );
            iteration += 1;
        }

        if terminal_event == "stopped" {
            println!("[Swirl][Workflow][{}] stopped", thread_run_id);
            emit(
                &thread_app,
                run_event(
                    "stopped",
                    &thread_run_id,
                    iteration,
                    None,
                    Some("idle"),
                    Some("Workflow stopped".into()),
                    None,
                ),
            );
        }
        if let Ok(mut active) = thread_app.state::<WorkflowRunState>().0.lock() {
            active.remove(&thread_run_id);
        }
    });

    Ok(json!({ "runId": run_id, "runMode": run_mode }))
}

#[tauri::command]
fn stop_workflow(run_id: String, runs: State<'_, WorkflowRunState>) -> Result<Value, String> {
    let active = runs.0.lock().map_err(|error| error.to_string())?;
    let Some(cancelled) = active.get(&run_id) else {
        return Ok(json!({ "stopped": false, "runId": run_id }));
    };
    cancelled.store(true, Ordering::Relaxed);
    println!("[Swirl][Workflow][{run_id}] stop requested");
    Ok(json!({ "stopped": true, "runId": run_id }))
}

#[tauri::command]
fn execute_mac_action(request: MacActionRequest) -> MacActionResult {
    macos::execute(&request)
}

#[tauri::command]
fn execute_mac_applescript(script: String) -> MacActionResult {
    macos::execute_restricted_applescript(&script)
}

#[tauri::command]
fn execute_mac_shell(command: String, approved: Option<bool>) -> MacActionResult {
    macos::execute(&MacActionRequest {
        app: "Terminal".into(),
        action: "exec_shell".into(),
        params: json!({ "command": command }),
        approved: approved.unwrap_or(false),
    })
}

#[tauri::command]
fn register_mcp_server(config: McpServerConfig, state: State<'_, McpState>) -> Result<(), String> {
    state
        .0
        .lock()
        .map_err(|error| error.to_string())?
        .register(config)
}

#[tauri::command]
fn list_mcp_servers(state: State<'_, McpState>) -> Result<Vec<McpServerConfig>, String> {
    Ok(state.0.lock().map_err(|error| error.to_string())?.configs())
}

#[tauri::command]
fn remove_mcp_server(name: String, state: State<'_, McpState>) -> Result<bool, String> {
    state
        .0
        .lock()
        .map_err(|error| error.to_string())?
        .remove(&name)
}

#[tauri::command]
fn discover_mcp_tools(name: String, state: State<'_, McpState>) -> Result<Value, String> {
    state
        .0
        .lock()
        .map_err(|error| error.to_string())?
        .discover(&name)
}

#[tauri::command]
fn call_mcp_tool(
    name: String,
    tool: String,
    arguments: Value,
    state: State<'_, McpState>,
) -> Result<Value, String> {
    state
        .0
        .lock()
        .map_err(|error| error.to_string())?
        .call(&name, &tool, arguments)
}

#[tauri::command]
fn list_builtin_mcp_servers(app: AppHandle) -> Result<Value, String> {
    jac_runtime::invoke(&app, "mcp-servers", &json!({}))
}

fn builtin_mcp_configs(app: &AppHandle) -> Vec<McpServerConfig> {
    let value = match jac_runtime::invoke(app, "mcp-servers", &json!({})) {
        Ok(value) => value,
        Err(error) => {
            eprintln!("[Swirl][MCP] could not load Jac server catalog: {error}");
            return Vec::new();
        }
    };
    let mut configs: Vec<McpServerConfig> = match serde_json::from_value(
        value
            .get("servers")
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
    ) {
        Ok(configs) => configs,
        Err(error) => {
            eprintln!("[Swirl][MCP] invalid Jac server catalog: {error}");
            return Vec::new();
        }
    };
    let documents = app
        .path()
        .document_dir()
        .ok()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|| ".".into());
    for config in &mut configs {
        for argument in &mut config.args {
            if argument == "$SWIRL_DOCUMENTS" {
                *argument = documents.clone();
            }
        }
    }
    println!(
        "[Swirl][MCP] loaded {} built-in server definition(s) from Jac",
        configs.len()
    );
    configs
}

#[tauri::command]
fn save_workflow(
    app: AppHandle,
    name: String,
    workflow: WorkflowDocument,
) -> Result<storage::WorkflowRecord, String> {
    storage::save_workflow(&app, &name, workflow)
}

#[tauri::command]
fn load_workflow(app: AppHandle, name: String) -> Result<storage::WorkflowRecord, String> {
    storage::load_workflow(&app, &name)
}

#[tauri::command]
fn list_workflows(app: AppHandle) -> Result<Vec<storage::WorkflowRecord>, String> {
    storage::list_workflows(&app)
}

#[tauri::command]
fn delete_workflow(app: AppHandle, name: String) -> Result<bool, String> {
    storage::delete_workflow(&app, &name)
}

#[tauri::command]
fn toggle_notch(app: AppHandle) -> Result<bool, String> {
    if let Some(notch_window) = app.get_webview_window("notch") {
        let is_visible = notch_window.is_visible().unwrap_or(false);
        if is_visible {
            let _ = notch_window.hide();
            Ok(false)
        } else {
            let _ = notch_window.show();
            Ok(true)
        }
    } else {
        Err("Notch window not found".into())
    }
}

fn main() {
    use tauri_plugin_global_shortcut::{
        Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState,
    };

    let app = tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let builtins = builtin_mcp_configs(app.handle());
            app.manage(McpState(std::sync::Mutex::new(McpManager::load(
                app.handle(),
                builtins,
            ))));
            app.manage(WorkflowRunState::default());

            if let Some(notch_win) = app.get_webview_window("notch") {
                if let Ok(Some(monitor)) = notch_win.primary_monitor() {
                    let size = monitor.size();
                    let scale = monitor.scale_factor();
                    let screen_width = (size.width as f64) / scale;
                    let notch_x = (screen_width - 180.0) / 2.0;
                    let _ =
                        notch_win.set_position(tauri::Position::Logical(tauri::LogicalPosition {
                            x: notch_x,
                            y: 0.0,
                        }));
                }
            }

            let shortcut_space = Shortcut::new(
                Some(Modifiers::CONTROL | Modifiers::ALT | Modifiers::SUPER),
                Code::Space,
            );
            let app_handle = app.handle().clone();
            let _ =
                app.global_shortcut()
                    .on_shortcut(shortcut_space, move |_app, _shortcut, event| {
                        if event.state() == ShortcutState::Pressed {
                            if let Some(notch_win) = app_handle.get_webview_window("notch") {
                                if notch_win.is_visible().unwrap_or(false) {
                                    let _ = notch_win.hide();
                                } else {
                                    let _ = notch_win.show();
                                }
                            }
                        }
                    });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            backend_health,
            compile_prompt,
            generate_jac_source,
            execute_workflow,
            start_workflow,
            stop_workflow,
            execute_mac_action,
            execute_mac_applescript,
            execute_mac_shell,
            register_mcp_server,
            list_mcp_servers,
            remove_mcp_server,
            discover_mcp_tools,
            call_mcp_tool,
            list_builtin_mcp_servers,
            save_workflow,
            load_workflow,
            list_workflows,
            delete_workflow,
            toggle_notch
        ])
        .build(tauri::generate_context!())
        .expect("error while building Swirl Tauri desktop application");

    app.run(|app_handle, event| {
        if matches!(
            event,
            tauri::RunEvent::Exit | tauri::RunEvent::ExitRequested { .. }
        ) {
            if let Ok(active) = app_handle.state::<WorkflowRunState>().0.lock() {
                for cancelled in active.values() {
                    cancelled.store(true, Ordering::Relaxed);
                }
            }
            if let Ok(mut manager) = app_handle.state::<McpState>().0.lock() {
                manager.stop_all();
            }
        }
    });
}

#[cfg(test)]
mod execution_tests {
    use super::*;

    #[test]
    fn local_email_fallback_creates_a_real_summary() {
        let email = json!({
            "subject": "Project update",
            "sender": "person@example.com"
        });
        let (summary, actions) = local_email_summary(
            "The project is on schedule. Please send the final review by Friday. Thanks.",
            Some(&email),
        );
        assert!(summary.contains("Subject: Project update"));
        assert!(summary.contains("The project is on schedule."));
        assert!(summary.contains("Action items:"));
        assert_eq!(actions.len(), 1);
        assert!(!summary.contains("LLM transform prepared"));
    }
}
