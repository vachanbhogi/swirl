//! Safe, reusable application-tool preparation and execution.
//!
//! Jac owns generation and persistence. This module is the native trust
//! boundary: it resolves real installed applications, accepts only a small
//! typed Accessibility DSL, compiles it to reviewable AppleScript, and keeps
//! all runtime values in `run argv` rather than executable source.

use crate::models::{
    AccessibilitySelector, AutomationStep, GeneratedAppToolDraft, GeneratedToolEffect,
    GeneratedToolInput, GeneratedToolRef, GeneratedToolSnapshot, GeneratedToolTarget,
    ToolValidation,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{Mutex, OnceLock},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const MAX_PROGRAM_STEPS: usize = 64;
const MAX_INPUTS: usize = 24;
const MAX_WAIT_SECONDS: f64 = 15.0;
const MAX_SELECTOR_LENGTH: usize = 180;

static GUI_AUTOMATION_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InstalledApplication {
    pub application_name: String,
    pub bundle_id: String,
    pub process_name: String,
    pub observed_version: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CompiledAutomation {
    /// A disclosure/review artifact. It contains no recipient, message, or
    /// other runtime binding value.
    pub source: String,
    pub argv_order: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PreparedGeneratedTool {
    pub name: String,
    pub description: String,
    pub source_prompt: String,
    pub application_query: String,
    pub target: GeneratedToolTarget,
    pub inputs: Vec<GeneratedToolInput>,
    pub program: Vec<AutomationStep>,
    pub effects: Vec<GeneratedToolEffect>,
    pub permissions: Vec<String>,
    pub risk: String,
    pub validation: ToolValidation,
    pub test_status: String,
    pub fingerprint: String,
    pub compiled_automation: CompiledAutomation,
}

impl PreparedGeneratedTool {
    pub fn snapshot(&self) -> GeneratedToolSnapshot {
        GeneratedToolSnapshot {
            target: self.target.clone(),
            inputs: self.inputs.clone(),
            program: self.program.clone(),
            effects: self.effects.clone(),
            permissions: self.permissions.clone(),
            risk: self.risk.clone(),
            validation: self.validation.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppConnectionCheck {
    pub installed: bool,
    pub running: bool,
    pub frontmost: bool,
    pub accessibility_ready: bool,
    pub observed_version: String,
    pub version_matches: bool,
    pub status: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppToolExecutionResult {
    pub success: bool,
    pub output: BTreeMap<String, String>,
    pub effects: Vec<GeneratedToolEffect>,
    pub duration_ms: u128,
    pub completed_steps: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppToolLogEvent {
    pub tool_id: String,
    pub version: u64,
    pub application: String,
    pub validation: String,
    pub approval_state: String,
    pub step_number: usize,
    pub step_type: String,
    pub duration_ms: u128,
    pub result: String,
}

fn normalized(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn string_literal(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn plist_json(path: &Path) -> Result<Value, String> {
    let output = Command::new("/usr/bin/plutil")
        .args(["-convert", "json", "-o", "-"])
        .arg(path)
        .output()
        .map_err(|error| format!("Cannot inspect {}: {error}", path.display()))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    serde_json::from_slice(&output.stdout).map_err(|error| {
        format!(
            "Invalid application metadata at {}: {error}",
            path.display()
        )
    })
}

fn scan_app_directory(directory: &Path, depth: usize, found: &mut Vec<PathBuf>) {
    if depth > 3 {
        return;
    }
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) == Some("app") {
            found.push(path);
        } else if path.is_dir() {
            scan_app_directory(&path, depth + 1, found);
        }
    }
}

pub fn discover_installed_apps() -> Result<Vec<InstalledApplication>, String> {
    let mut bundles = Vec::new();
    for directory in [
        PathBuf::from("/Applications"),
        PathBuf::from("/System/Applications"),
        PathBuf::from("/System/Applications/Utilities"),
    ] {
        scan_app_directory(&directory, 0, &mut bundles);
    }
    if let Some(home) = std::env::var_os("HOME") {
        scan_app_directory(&PathBuf::from(home).join("Applications"), 0, &mut bundles);
    }

    bundles.sort();
    bundles.dedup();
    let mut apps = Vec::new();
    for bundle in bundles {
        let info_path = bundle.join("Contents/Info.plist");
        let Ok(info) = plist_json(&info_path) else {
            continue;
        };
        let bundle_id = info
            .get("CFBundleIdentifier")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim();
        if bundle_id.is_empty() {
            continue;
        }
        let fallback_name = bundle
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("Application");
        let name = info
            .get("CFBundleDisplayName")
            .or_else(|| info.get("CFBundleName"))
            .and_then(Value::as_str)
            .unwrap_or(fallback_name)
            .trim();
        let process_name = info
            .get("CFBundleExecutable")
            .and_then(Value::as_str)
            .unwrap_or(name)
            .trim();
        let version = info
            .get("CFBundleShortVersionString")
            .or_else(|| info.get("CFBundleVersion"))
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim();
        apps.push(InstalledApplication {
            application_name: name.to_string(),
            bundle_id: bundle_id.to_string(),
            process_name: process_name.to_string(),
            observed_version: version.to_string(),
            path: bundle.to_string_lossy().into_owned(),
        });
    }
    apps.sort_by(|a, b| {
        a.application_name
            .to_ascii_lowercase()
            .cmp(&b.application_name.to_ascii_lowercase())
            .then_with(|| a.bundle_id.cmp(&b.bundle_id))
    });
    if apps.is_empty() {
        return Err("No installed macOS application bundles could be discovered".into());
    }
    Ok(apps)
}

fn unsupported_application(app: &InstalledApplication) -> bool {
    let identity = format!(
        "{} {} {}",
        app.application_name, app.bundle_id, app.process_name
    )
    .to_ascii_lowercase();
    [
        "terminal",
        "keychain access",
        "com.apple.keychainaccess",
        "script editor",
    ]
    .iter()
    .any(|blocked| identity.contains(blocked))
}

fn target_from_app(app: &InstalledApplication) -> GeneratedToolTarget {
    GeneratedToolTarget {
        application_name: app.application_name.clone(),
        bundle_id: app.bundle_id.clone(),
        process_name: app.process_name.clone(),
        observed_version: app.observed_version.clone(),
        automation_mode: "accessibility".into(),
    }
}

pub fn resolve_installed_app(query: &str) -> Result<GeneratedToolTarget, String> {
    let query = query.trim();
    if query.is_empty() {
        return Err("The generated tool did not name an application".into());
    }
    let normalized_query = normalized(query);
    if normalized_query.is_empty() {
        return Err("The application query is invalid".into());
    }
    let apps = discover_installed_apps()?;
    let exact = apps
        .iter()
        .filter(|app| {
            [
                app.application_name.as_str(),
                app.bundle_id.as_str(),
                app.process_name.as_str(),
            ]
            .iter()
            .any(|candidate| normalized(candidate) == normalized_query)
        })
        .collect::<Vec<_>>();
    let matches = if exact.is_empty() {
        apps.iter()
            .filter(|app| {
                [
                    app.application_name.as_str(),
                    app.bundle_id.as_str(),
                    app.process_name.as_str(),
                ]
                .iter()
                .any(|candidate| normalized(candidate).contains(&normalized_query))
            })
            .collect::<Vec<_>>()
    } else {
        exact
    };

    if matches.is_empty() {
        return Err(format!(
            "No installed application matches '{query}'. Install it or correct the application name."
        ));
    }
    if matches.len() > 1 {
        let choices = matches
            .iter()
            .take(8)
            .map(|app| format!("{} ({})", app.application_name, app.bundle_id))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!(
            "'{query}' matches multiple installed applications: {choices}. Use a more specific name."
        ));
    }
    let app = matches[0];
    if unsupported_application(app) {
        return Err(format!(
            "{} is not supported for generated tools because it can execute code or access secrets",
            app.application_name
        ));
    }
    Ok(target_from_app(app))
}

pub fn snapshot_from_draft(
    draft: &GeneratedAppToolDraft,
    target: GeneratedToolTarget,
) -> GeneratedToolSnapshot {
    GeneratedToolSnapshot {
        target,
        inputs: draft.inputs.clone(),
        program: draft.program.clone(),
        effects: draft.effects.clone(),
        permissions: draft.permissions.clone(),
        risk: draft.risk.clone(),
        validation: draft.validation.clone(),
    }
}

fn validate_text(label: &str, value: &str, max: usize) -> Result<(), String> {
    if value.trim().is_empty() || value.chars().count() > max || value.contains('\0') {
        return Err(format!("{label} must be 1-{max} characters"));
    }
    if value.chars().any(|character| character.is_control()) {
        return Err(format!("{label} cannot contain control characters"));
    }
    Ok(())
}

fn valid_input_key(key: &str) -> bool {
    let mut characters = key.chars();
    matches!(characters.next(), Some(character) if character.is_ascii_lowercase())
        && characters.all(|character| {
            character.is_ascii_lowercase() || character.is_ascii_digit() || character == '_'
        })
        && key.len() <= 64
}

fn validate_selector(selector: &AccessibilitySelector) -> Result<(), String> {
    if selector.role.is_none() && selector.title.is_none() && selector.identifier.is_none() {
        return Err("Accessibility selectors require a role, title, or identifier".into());
    }
    if let Some(role) = selector.role.as_deref() {
        const ROLES: &[&str] = &[
            "AXButton",
            "AXCheckBox",
            "AXComboBox",
            "AXGroup",
            "AXLink",
            "AXMenuItem",
            "AXPopUpButton",
            "AXRadioButton",
            "AXRow",
            "AXSearchField",
            "AXStaticText",
            "AXTabGroup",
            "AXTextArea",
            "AXTextField",
            "AXToolbar",
        ];
        if !ROLES.contains(&role) {
            return Err(format!("Accessibility role '{role}' is not allowlisted"));
        }
    }
    for (label, value) in [
        ("selector role", selector.role.as_deref()),
        ("selector title", selector.title.as_deref()),
        ("selector identifier", selector.identifier.as_deref()),
    ] {
        if let Some(value) = value {
            validate_text(label, value, MAX_SELECTOR_LENGTH)?;
        }
    }
    Ok(())
}

fn validate_wait(label: &str, seconds: f64) -> Result<(), String> {
    if !seconds.is_finite() || !(0.05..=MAX_WAIT_SECONDS).contains(&seconds) {
        return Err(format!(
            "{label} must be between 0.05 and {MAX_WAIT_SECONDS} seconds"
        ));
    }
    Ok(())
}

fn validate_step(step: &AutomationStep, inputs: &HashSet<String>) -> Result<(), String> {
    match step {
        AutomationStep::ActivateApp => Ok(()),
        AutomationStep::Wait { seconds } => validate_wait("wait", *seconds),
        AutomationStep::WaitFrontmost { timeout_sec } => {
            validate_wait("frontmost timeout", *timeout_sec)
        }
        AutomationStep::KeyChord { keys } => {
            if keys.len() < 2 || keys.len() > 4 {
                return Err("key_chord requires one key and 1-3 modifiers".into());
            }
            let modifiers = ["command", "option", "control", "shift"];
            let modifier_count = keys
                .iter()
                .filter(|key| modifiers.contains(&key.to_ascii_lowercase().as_str()))
                .count();
            let ordinary = keys
                .iter()
                .filter(|key| !modifiers.contains(&key.to_ascii_lowercase().as_str()))
                .collect::<Vec<_>>();
            if modifier_count + ordinary.len() != keys.len()
                || modifier_count == 0
                || ordinary.len() != 1
                || ordinary[0].chars().count() != 1
                || ordinary[0].chars().any(char::is_control)
            {
                return Err(
                    "key_chord requires allowlisted modifiers and one printable key".into(),
                );
            }
            Ok(())
        }
        AutomationStep::PressKey { key } => {
            const KEYS: &[&str] = &[
                "return",
                "enter",
                "tab",
                "escape",
                "space",
                "up",
                "down",
                "left",
                "right",
                "home",
                "end",
                "page_up",
                "page_down",
            ];
            if !KEYS.contains(&key.to_ascii_lowercase().as_str()) {
                return Err(format!("named key '{key}' is not allowlisted"));
            }
            Ok(())
        }
        AutomationStep::TypeInput { input_key } => {
            if !inputs.contains(input_key) {
                return Err(format!("type_input references unknown input '{input_key}'"));
            }
            Ok(())
        }
        AutomationStep::WaitElement {
            selector,
            timeout_sec,
        } => {
            validate_selector(selector)?;
            validate_wait("element timeout", *timeout_sec)
        }
        AutomationStep::ClickElement { selector }
        | AutomationStep::ReadElement { selector, .. } => validate_selector(selector),
    }
}

pub fn validate_tool_snapshot(snapshot: &GeneratedToolSnapshot) -> Result<ToolValidation, String> {
    if snapshot.target.automation_mode != "accessibility" {
        return Err("Only the Accessibility automation mode is supported".into());
    }
    validate_text("application name", &snapshot.target.application_name, 120)?;
    validate_text("bundle identifier", &snapshot.target.bundle_id, 240)?;
    validate_text("process name", &snapshot.target.process_name, 160)?;
    let identity = format!(
        "{} {} {}",
        snapshot.target.application_name, snapshot.target.bundle_id, snapshot.target.process_name
    )
    .to_ascii_lowercase();
    if ["terminal", "keychain", "script editor"]
        .iter()
        .any(|blocked| identity.contains(blocked))
    {
        return Err("Generated tools cannot target Terminal, Keychain, or Script Editor".into());
    }
    if snapshot.inputs.len() > MAX_INPUTS {
        return Err(format!(
            "Generated tools support at most {MAX_INPUTS} inputs"
        ));
    }
    let mut input_keys = HashSet::new();
    for input in &snapshot.inputs {
        if !valid_input_key(&input.key) {
            return Err(format!(
                "Input key '{}' must start with a lowercase letter and contain only lowercase letters, digits, or underscores",
                input.key
            ));
        }
        if !input_keys.insert(input.key.clone()) {
            return Err(format!("Input key '{}' is duplicated", input.key));
        }
        validate_text("input label", &input.label, 100)?;
        if input.input_type != "string" {
            return Err(format!(
                "Input '{}' uses unsupported type '{}'",
                input.key, input.input_type
            ));
        }
        if input.default_value.chars().count() > 4_096 || input.default_value.contains('\0') {
            return Err(format!(
                "Default for '{}' is too long or invalid",
                input.key
            ));
        }
    }
    if snapshot.program.is_empty() || snapshot.program.len() > MAX_PROGRAM_STEPS {
        return Err(format!(
            "Automation programs must contain 1-{MAX_PROGRAM_STEPS} steps"
        ));
    }
    if !matches!(snapshot.program.first(), Some(AutomationStep::ActivateApp)) {
        return Err("The first automation step must be activate_app".into());
    }
    for (index, step) in snapshot.program.iter().enumerate() {
        validate_step(step, &input_keys)
            .map_err(|error| format!("Step {} ({}): {error}", index + 1, step.kind()))?;
    }
    let can_change_application_state = snapshot.program.iter().any(|step| {
        matches!(
            step,
            AutomationStep::KeyChord { .. }
                | AutomationStep::PressKey { .. }
                | AutomationStep::TypeInput { .. }
                | AutomationStep::ClickElement { .. }
        )
    });
    if can_change_application_state && snapshot.effects.is_empty() {
        return Err(
            "A program that types, presses keys, or clicks must disclose at least one external effect"
                .into(),
        );
    }
    for effect in &snapshot.effects {
        validate_text("effect type", &effect.effect_type, 80)?;
        validate_text("effect description", &effect.description, 240)?;
        let lowered = effect.effect_type.to_ascii_lowercase();
        if ["delete", "purchase", "download", "shell", "keychain"]
            .iter()
            .any(|blocked| lowered.contains(blocked))
        {
            return Err(format!(
                "Effect '{}' is not allowed for generated tools",
                effect.effect_type
            ));
        }
        if can_change_application_state && !effect.requires_approval {
            return Err(format!(
                "Effect '{}' must require one-shot approval",
                effect.effect_type
            ));
        }
    }
    let mut permissions = snapshot
        .permissions
        .iter()
        .map(|permission| permission.to_ascii_lowercase())
        .collect::<Vec<_>>();
    permissions.sort();
    permissions.dedup();
    if permissions
        .iter()
        .any(|permission| !matches!(permission.as_str(), "accessibility" | "automation"))
    {
        return Err(
            "Generated tools may request only Accessibility and Automation permissions".into(),
        );
    }
    Ok(ToolValidation {
        valid: true,
        status: "validated".into(),
        messages: vec![
            "Typed automation program passed the native allowlist".into(),
            "AppleScript is compiled for review; runtime values remain argv-only".into(),
        ],
    })
}

fn selector_parts(selector: &AccessibilitySelector) -> (String, String, String) {
    (
        string_literal(selector.role.as_deref().unwrap_or("")),
        string_literal(selector.title.as_deref().unwrap_or("")),
        string_literal(selector.identifier.as_deref().unwrap_or("")),
    )
}

fn key_code(key: &str) -> Option<u16> {
    match key.to_ascii_lowercase().as_str() {
        "return" | "enter" => Some(36),
        "tab" => Some(48),
        "escape" => Some(53),
        "space" => Some(49),
        "left" => Some(123),
        "right" => Some(124),
        "down" => Some(125),
        "up" => Some(126),
        "home" => Some(115),
        "end" => Some(119),
        "page_up" => Some(116),
        "page_down" => Some(121),
        _ => None,
    }
}

fn trace_start(source: &mut String, step_number: usize, step: &AutomationStep) {
    source.push_str(&format!(
        "\t\tset currentStep to {step_number}\n\t\tset currentStepType to {}\n",
        string_literal(step.kind())
    ));
}

fn trace_finish(source: &mut String, step_number: usize, step: &AutomationStep) {
    source.push_str(&format!(
        "\t\tset traceLines to traceLines & \"SWIRL_TRACE\\t{step_number}\\t{}\\t0\" & linefeed\n",
        step.kind()
    ));
}

fn compile_step(
    source: &mut String,
    step: &AutomationStep,
    argv_indexes: &HashMap<String, usize>,
    target: &GeneratedToolTarget,
    ordinal: usize,
) -> Result<(), String> {
    let process = string_literal(&target.process_name);
    let application = string_literal(&target.application_name);
    trace_start(source, ordinal, step);
    match step {
        AutomationStep::ActivateApp => {
            source.push_str(&format!("\t\ttell application {application} to activate\n"));
        }
        AutomationStep::Wait { seconds } => {
            source.push_str(&format!("\t\tdelay {seconds:.3}\n"));
        }
        AutomationStep::WaitFrontmost { timeout_sec } => {
            let attempts = (*timeout_sec * 10.0).ceil() as u32;
            source.push_str(&format!(
                "\t\tset focusReady to false\n\t\trepeat with waitAttempt from 1 to {attempts}\n\t\t\tif my targetIsFrontmost({process}) then\n\t\t\t\tset focusReady to true\n\t\t\t\texit repeat\n\t\t\tend if\n\t\t\tdelay 0.1\n\t\tend repeat\n\t\tif not focusReady then error \"Target application did not become frontmost\"\n"
            ));
        }
        AutomationStep::KeyChord { keys } => {
            let modifiers = keys
                .iter()
                .filter_map(|key| match key.to_ascii_lowercase().as_str() {
                    "command" => Some("command down"),
                    "option" => Some("option down"),
                    "control" => Some("control down"),
                    "shift" => Some("shift down"),
                    _ => None,
                })
                .collect::<Vec<_>>();
            let key = keys
                .iter()
                .find(|key| {
                    !["command", "option", "control", "shift"]
                        .contains(&key.to_ascii_lowercase().as_str())
                })
                .ok_or_else(|| "key_chord omitted its printable key".to_string())?;
            source.push_str(&format!(
                "\t\tmy assertTargetFrontmost({process})\n\t\ttell application \"System Events\" to keystroke {} using {{{}}}\n",
                string_literal(key),
                modifiers.join(", ")
            ));
        }
        AutomationStep::PressKey { key } => {
            let code = key_code(key).ok_or_else(|| format!("Unsupported named key '{key}'"))?;
            source.push_str(&format!(
                "\t\tmy assertTargetFrontmost({process})\n\t\ttell application \"System Events\" to key code {code}\n"
            ));
        }
        AutomationStep::TypeInput { input_key } => {
            let index = argv_indexes
                .get(input_key)
                .ok_or_else(|| format!("No argv slot exists for input '{input_key}'"))?;
            source.push_str(&format!(
                "\t\tmy assertTargetFrontmost({process})\n\t\ttell application \"System Events\" to keystroke (item {index} of argv)\n"
            ));
        }
        AutomationStep::WaitElement {
            selector,
            timeout_sec,
        } => {
            let (role, title, identifier) = selector_parts(selector);
            let attempts = (*timeout_sec * 10.0).ceil() as u32;
            source.push_str(&format!(
                "\t\tset foundElement to missing value\n\t\trepeat with waitAttempt from 1 to {attempts}\n\t\t\tmy assertTargetFrontmost({process})\n\t\t\ttry\n\t\t\t\tset foundElement to my findTargetElement({process}, {role}, {title}, {identifier})\n\t\t\tend try\n\t\t\tif foundElement is not missing value then exit repeat\n\t\t\tdelay 0.1\n\t\tend repeat\n\t\tif foundElement is missing value then error \"Accessibility element was not found before timeout\"\n"
            ));
        }
        AutomationStep::ClickElement { selector } => {
            let (role, title, identifier) = selector_parts(selector);
            source.push_str(&format!(
                "\t\tmy assertTargetFrontmost({process})\n\t\tset foundElement to my findTargetElement({process}, {role}, {title}, {identifier})\n\t\ttell application \"System Events\" to perform action \"AXPress\" of foundElement\n"
            ));
        }
        AutomationStep::ReadElement {
            selector,
            output_key,
        } => {
            let (role, title, identifier) = selector_parts(selector);
            let output_key = if output_key.is_empty() {
                format!("step_{ordinal}")
            } else {
                output_key.clone()
            };
            if !valid_input_key(&output_key) {
                return Err(format!("Read output key '{output_key}' is invalid"));
            }
            source.push_str(&format!(
                "\t\tmy assertTargetFrontmost({process})\n\t\tset foundElement to my findTargetElement({process}, {role}, {title}, {identifier})\n\t\ttell application \"System Events\" to set foundValue to value of foundElement as text\n\t\tset outputLines to outputLines & \"SWIRL_OUTPUT\\t{}\\t\" & foundValue & linefeed\n",
                output_key
            ));
        }
    }
    trace_finish(source, ordinal, step);
    Ok(())
}

pub fn compile_reviewable_applescript(
    snapshot: &GeneratedToolSnapshot,
) -> Result<CompiledAutomation, String> {
    validate_tool_snapshot(snapshot)?;
    let argv_order = snapshot
        .inputs
        .iter()
        .map(|input| input.key.clone())
        .collect::<Vec<_>>();
    let argv_indexes = argv_order
        .iter()
        .enumerate()
        .map(|(index, key)| (key.clone(), index + 1))
        .collect::<HashMap<_, _>>();
    let mut source = String::from(
        "-- Generated by Swirl from a validated typed program.\n\
on targetIsFrontmost(targetProcessName)\n\
\ttell application \"System Events\"\n\
\t\tif not (exists (first application process whose name is targetProcessName)) then return false\n\
\t\treturn frontmost of first application process whose name is targetProcessName\n\
\tend tell\n\
end targetIsFrontmost\n\n\
on assertTargetFrontmost(targetProcessName)\n\
\tif not my targetIsFrontmost(targetProcessName) then error \"Focus left the target application; automation aborted\"\n\
end assertTargetFrontmost\n\n\
on findTargetElement(targetProcessName, targetRole, targetTitle, targetIdentifier)\n\
\ttell application \"System Events\"\n\
\t\tset targetProcess to first application process whose name is targetProcessName\n\
\t\tset candidates to entire contents of targetProcess\n\
\t\trepeat with candidate in candidates\n\
\t\t\ttry\n\
\t\t\t\tset roleMatches to true\n\
\t\t\t\tif targetRole is not \"\" then set roleMatches to ((role of candidate as text) is targetRole)\n\
\t\t\t\tset titleMatches to true\n\
\t\t\t\tif targetTitle is not \"\" then set titleMatches to ((title of candidate as text) is targetTitle)\n\
\t\t\t\tset identifierMatches to true\n\
\t\t\t\tif targetIdentifier is not \"\" then set identifierMatches to ((value of attribute \"AXIdentifier\" of candidate as text) is targetIdentifier)\n\
\t\t\t\tif roleMatches and titleMatches and identifierMatches then return candidate\n\
\t\t\tend try\n\
\t\tend repeat\n\
\tend tell\n\
\terror \"Accessibility element not found\"\n\
end findTargetElement\n\n\
on run argv\n\
\tset currentStep to 0\n\
\tset currentStepType to \"none\"\n\
\tset traceLines to \"\"\n\
\tset outputLines to \"\"\n\
\ttry\n",
    );
    for (index, step) in snapshot.program.iter().enumerate() {
        compile_step(
            &mut source,
            step,
            &argv_indexes,
            &snapshot.target,
            index + 1,
        )?;
    }
    source.push_str(
        "\t\treturn traceLines & outputLines\n\
\ton error errorMessage number errorNumber\n\
\t\terror \"SWIRL_STEP_FAILURE\\t\" & currentStep & \"\\t\" & currentStepType & \"\\t\" & errorMessage number errorNumber\n\
\tend try\n\
end run\n",
    );
    Ok(CompiledAutomation { source, argv_order })
}

fn compile_output_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_nanos();
    std::env::temp_dir().join(format!(
        "swirl-tool-compile-{}-{timestamp}.scpt",
        std::process::id()
    ))
}

pub fn validate_compiled_applescript(source: &str) -> Result<(), String> {
    if source.is_empty() || source.len() > 96_000 || source.contains('\0') {
        return Err("Compiled automation disclosure is empty or too large".into());
    }
    let output_path = compile_output_path();
    let output = Command::new("/usr/bin/osacompile")
        .arg("-o")
        .arg(&output_path)
        .arg("-e")
        .arg(source)
        .output()
        .map_err(|error| format!("Could not run osacompile: {error}"))?;
    let _ = fs::remove_file(&output_path);
    if !output.status.success() {
        return Err(format!(
            "Generated automation did not compile: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(())
}

fn canonical_json(value: &Value) -> String {
    match value {
        Value::Object(object) => {
            let mut keys = object.keys().collect::<Vec<_>>();
            keys.sort();
            format!(
                "{{{}}}",
                keys.iter()
                    .map(|key| format!(
                        "{}:{}",
                        serde_json::to_string(key).unwrap_or_else(|_| "\"\"".into()),
                        canonical_json(&object[*key])
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
        Value::Array(items) => format!(
            "[{}]",
            items
                .iter()
                .map(canonical_json)
                .collect::<Vec<_>>()
                .join(",")
        ),
        _ => serde_json::to_string(value).unwrap_or_else(|_| "null".into()),
    }
}

fn sha256(value: &str) -> String {
    format!("{:x}", Sha256::digest(value.as_bytes()))
}

pub fn fingerprint_snapshot(snapshot: &GeneratedToolSnapshot) -> Result<String, String> {
    let value = serde_json::to_value(snapshot)
        .map_err(|error| format!("Cannot fingerprint generated tool snapshot: {error}"))?;
    Ok(sha256(&canonical_json(&value)))
}

pub fn verify_tool_fingerprint(
    tool_ref: &GeneratedToolRef,
    snapshot: &GeneratedToolSnapshot,
) -> Result<(), String> {
    let actual = fingerprint_snapshot(snapshot)?;
    if tool_ref.fingerprint != actual {
        return Err(format!(
            "Pinned tool {} v{} has a stale or modified fingerprint; review an updated version before running",
            tool_ref.id, tool_ref.version
        ));
    }
    Ok(())
}

pub fn digest_resolved_arguments(fingerprint: &str, values: &HashMap<String, String>) -> String {
    let sorted = values.iter().collect::<BTreeMap<_, _>>();
    let mut hasher = Sha256::new();
    hasher.update(fingerprint.as_bytes());
    for (key, value) in sorted {
        hasher.update([0]);
        hasher.update(key.as_bytes());
        hasher.update([0]);
        hasher.update(value.as_bytes());
    }
    format!("{:x}", hasher.finalize())
}

pub fn prepare_generated_tool_draft(raw: Value) -> Result<PreparedGeneratedTool, String> {
    let raw = raw.get("draft").cloned().unwrap_or(raw);
    let draft: GeneratedAppToolDraft = serde_json::from_value(raw)
        .map_err(|error| format!("Jac returned a malformed generated tool: {error}"))?;
    validate_text("tool name", &draft.name, 100)?;
    validate_text("tool description", &draft.description, 500)?;
    validate_text("source prompt", &draft.source_prompt, 4_000)?;
    let target = resolve_installed_app(&draft.application_query)?;
    let mut snapshot = snapshot_from_draft(&draft, target.clone());
    let validation = validate_tool_snapshot(&snapshot)?;
    snapshot.validation = validation.clone();
    let compiled_automation = compile_reviewable_applescript(&snapshot)?;
    validate_compiled_applescript(&compiled_automation.source)?;
    let fingerprint = fingerprint_snapshot(&snapshot)?;
    Ok(PreparedGeneratedTool {
        name: draft.name,
        description: draft.description,
        source_prompt: draft.source_prompt,
        application_query: draft.application_query,
        target,
        inputs: snapshot.inputs,
        program: snapshot.program,
        effects: snapshot.effects,
        permissions: snapshot.permissions,
        risk: snapshot.risk,
        validation,
        test_status: "untested".into(),
        fingerprint,
        compiled_automation,
    })
}

fn installed_target(target: &GeneratedToolTarget) -> Result<InstalledApplication, String> {
    discover_installed_apps()?
        .into_iter()
        .find(|app| app.bundle_id == target.bundle_id)
        .ok_or_else(|| {
            format!(
                "{} ({}) is no longer installed",
                target.application_name, target.bundle_id
            )
        })
}

fn accessibility_state(process_name: &str) -> (bool, bool) {
    let script = format!(
        "tell application \"System Events\"\nset ready to UI elements enabled\nset isFrontmost to false\nif exists application process {} then set isFrontmost to frontmost of application process {}\nreturn (ready as text) & \"|\" & (isFrontmost as text)\nend tell",
        string_literal(process_name),
        string_literal(process_name)
    );
    let Ok(output) = Command::new("/usr/bin/osascript")
        .arg("-e")
        .arg(script)
        .output()
    else {
        return (false, false);
    };
    if !output.status.success() {
        return (false, false);
    }
    let text = String::from_utf8_lossy(&output.stdout).to_ascii_lowercase();
    let mut fields = text.trim().split('|');
    (fields.next() == Some("true"), fields.next() == Some("true"))
}

pub fn check_app_connection(target: &GeneratedToolTarget) -> Result<AppConnectionCheck, String> {
    let app = installed_target(target)?;
    let running = Command::new("/usr/bin/pgrep")
        .args(["-x", &target.process_name])
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    let (accessibility_ready, frontmost) = accessibility_state(&target.process_name);
    let version_matches =
        target.observed_version.is_empty() || target.observed_version == app.observed_version;
    let (status, message) = if !version_matches {
        (
            "app_updated",
            "The application version changed. Regenerate or review a new tool version.",
        )
    } else if !accessibility_ready {
        (
            "permission_required",
            "Enable Accessibility for Swirl in System Settings > Privacy & Security.",
        )
    } else if !running {
        (
            "not_running",
            "The app is installed but not running. Open it before live testing.",
        )
    } else if !frontmost {
        (
            "ready_not_focused",
            "Connection is ready. Bring the target app to the front before running.",
        )
    } else {
        (
            "ready",
            "Installation, focus, and Accessibility checks passed.",
        )
    };
    Ok(AppConnectionCheck {
        installed: true,
        running,
        frontmost,
        accessibility_ready,
        observed_version: app.observed_version,
        version_matches,
        status: status.into(),
        message: message.into(),
    })
}

fn resolved_argv(
    snapshot: &GeneratedToolSnapshot,
    values: &HashMap<String, String>,
) -> Result<Vec<String>, String> {
    snapshot
        .inputs
        .iter()
        .map(|input| {
            let value = values
                .get(&input.key)
                .cloned()
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| input.default_value.clone());
            if input.required && value.is_empty() {
                return Err(format!("Required input '{}' is missing", input.label));
            }
            if value.contains('\0') || value.chars().count() > 32_000 {
                return Err(format!("Input '{}' is too large or invalid", input.label));
            }
            Ok(value)
        })
        .collect()
}

fn parse_execution_output(
    stdout: &str,
) -> (usize, BTreeMap<String, String>, Vec<(usize, String, u128)>) {
    let mut completed = 0;
    let mut values = BTreeMap::new();
    let mut traces = Vec::new();
    for line in stdout.lines() {
        let parts = line.splitn(4, '\t').collect::<Vec<_>>();
        match parts.as_slice() {
            ["SWIRL_TRACE", number, kind, duration] => {
                if let (Ok(number), Ok(duration)) =
                    (number.parse::<usize>(), duration.parse::<u128>())
                {
                    completed = completed.max(number);
                    traces.push((number, (*kind).to_string(), duration));
                }
            }
            ["SWIRL_OUTPUT", key, value] => {
                values.insert((*key).to_string(), (*value).to_string());
            }
            _ => {}
        }
    }
    (completed, values, traces)
}

fn print_tool_event(event: &AppToolLogEvent) {
    println!(
        "[Swirl][GeneratedTool] id={} version={} app='{}' validation={} approval={} step={}:{} durationMs={} result={}",
        event.tool_id,
        event.version,
        event.application,
        event.validation,
        event.approval_state,
        event.step_number,
        event.step_type,
        event.duration_ms,
        event.result
    );
}

pub fn log_tool_event(
    tool_ref: &GeneratedToolRef,
    target: &GeneratedToolTarget,
    approval_state: &str,
    step_number: usize,
    step_type: &str,
    duration_ms: u128,
    result: &str,
) {
    print_tool_event(&AppToolLogEvent {
        tool_id: tool_ref.id.clone(),
        version: tool_ref.version,
        application: target.application_name.clone(),
        validation: "validated".into(),
        approval_state: approval_state.into(),
        step_number,
        step_type: step_type.into(),
        duration_ms,
        result: result.into(),
    });
}

pub fn execute_generated_app_tool(
    tool_ref: &GeneratedToolRef,
    snapshot: &GeneratedToolSnapshot,
    values: &HashMap<String, String>,
) -> Result<AppToolExecutionResult, String> {
    verify_tool_fingerprint(tool_ref, snapshot)?;
    validate_tool_snapshot(snapshot)?;
    let installed = installed_target(&snapshot.target)?;
    if !snapshot.target.observed_version.is_empty()
        && snapshot.target.observed_version != installed.observed_version
    {
        return Err(format!(
            "{} updated from version {} to {}. Review and publish a new tool version before running.",
            snapshot.target.application_name,
            snapshot.target.observed_version,
            installed.observed_version
        ));
    }
    let compiled = compile_reviewable_applescript(snapshot)?;
    validate_compiled_applescript(&compiled.source)?;
    let argv = resolved_argv(snapshot, values)?;
    let _guard = GUI_AUTOMATION_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .map_err(|_| "The global GUI automation lock is unavailable".to_string())?;
    let started = Instant::now();
    let mut child = Command::new("/usr/bin/osascript")
        .arg("-")
        .args(argv)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("Could not start approved automation: {error}"))?;
    child
        .stdin
        .as_mut()
        .ok_or_else(|| "Could not open automation input".to_string())?
        .write_all(compiled.source.as_bytes())
        .map_err(|error| format!("Could not send compiled automation to osascript: {error}"))?;
    let output = child
        .wait_with_output()
        .map_err(|error| format!("Approved automation failed to finish: {error}"))?;
    let duration_ms = started.elapsed().as_millis();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let (completed_steps, values, traces) = parse_execution_output(&stdout);
    for (step, step_type, step_duration) in traces {
        log_tool_event(
            tool_ref,
            &snapshot.target,
            "approved-once",
            step,
            &step_type,
            step_duration,
            "success",
        );
    }
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        eprintln!(
            "[Swirl][GeneratedTool] id={} version={} app='{}' validation=validated approval=approved-once durationMs={} result=failed (runtime values redacted)",
            tool_ref.id, tool_ref.version, snapshot.target.application_name, duration_ms
        );
        return Err(if error.is_empty() {
            "Approved automation failed without returning an error".into()
        } else {
            error
        });
    }
    Ok(AppToolExecutionResult {
        success: true,
        output: values,
        effects: snapshot.effects.clone(),
        duration_ms,
        completed_steps,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{GeneratedToolEffect, GeneratedToolInput};
    use serde_json::json;

    fn discord_snapshot() -> GeneratedToolSnapshot {
        GeneratedToolSnapshot {
            target: GeneratedToolTarget {
                application_name: "Discord".into(),
                bundle_id: "com.hnc.Discord".into(),
                process_name: "Discord".into(),
                observed_version: "1".into(),
                automation_mode: "accessibility".into(),
            },
            inputs: vec![
                GeneratedToolInput {
                    key: "recipient".into(),
                    label: "Recipient".into(),
                    input_type: "string".into(),
                    required: true,
                    default_value: String::new(),
                    sensitive: true,
                    description: String::new(),
                },
                GeneratedToolInput {
                    key: "message".into(),
                    label: "Message".into(),
                    input_type: "string".into(),
                    required: true,
                    default_value: String::new(),
                    sensitive: true,
                    description: String::new(),
                },
            ],
            program: vec![
                AutomationStep::ActivateApp,
                AutomationStep::WaitFrontmost { timeout_sec: 5.0 },
                AutomationStep::KeyChord {
                    keys: vec!["command".into(), "k".into()],
                },
                AutomationStep::TypeInput {
                    input_key: "recipient".into(),
                },
                AutomationStep::PressKey {
                    key: "return".into(),
                },
                AutomationStep::TypeInput {
                    input_key: "message".into(),
                },
                AutomationStep::PressKey {
                    key: "return".into(),
                },
            ],
            effects: vec![GeneratedToolEffect {
                effect_type: "send_message".into(),
                description: "Sends a message to a Discord recipient".into(),
                requires_approval: true,
            }],
            permissions: vec!["Accessibility".into(), "Automation".into()],
            risk: "high".into(),
            validation: ToolValidation::default(),
        }
    }

    #[test]
    fn compiler_never_embeds_runtime_values() {
        let snapshot = discord_snapshot();
        let compiled = compile_reviewable_applescript(&snapshot).unwrap();
        let malicious = "Alex\" & do shell script \"whoami\" & \"\n👋";
        assert!(!compiled.source.contains(malicious));
        assert!(compiled.source.contains("item 1 of argv"));
        assert!(compiled.source.contains("item 2 of argv"));
        assert_eq!(compiled.argv_order, vec!["recipient", "message"]);
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn compiled_program_passes_osacompile_without_execution() {
        let compiled = compile_reviewable_applescript(&discord_snapshot()).unwrap();
        validate_compiled_applescript(&compiled.source).unwrap();
    }

    #[test]
    fn malformed_or_forbidden_operations_do_not_deserialize() {
        let raw = json!({
            "target": {
                "applicationName": "Discord", "bundleId": "com.hnc.Discord",
                "processName": "Discord", "automationMode": "accessibility"
            },
            "inputs": [],
            "program": [{"op": "raw_applescript", "source": "do shell script \"whoami\""}],
            "effects": [], "permissions": [], "risk": "high", "validation": {}
        });
        assert!(serde_json::from_value::<GeneratedToolSnapshot>(raw).is_err());
    }

    #[test]
    fn validator_rejects_terminal_and_delete_effects() {
        let mut snapshot = discord_snapshot();
        snapshot.target.application_name = "Terminal".into();
        snapshot.target.bundle_id = "com.apple.Terminal".into();
        assert!(validate_tool_snapshot(&snapshot).is_err());

        let mut snapshot = discord_snapshot();
        snapshot.effects[0].effect_type = "delete_message".into();
        assert!(validate_tool_snapshot(&snapshot).is_err());
    }

    #[test]
    fn fingerprints_detect_snapshot_changes() {
        let mut snapshot = discord_snapshot();
        snapshot.validation = validate_tool_snapshot(&snapshot).unwrap();
        let fingerprint = fingerprint_snapshot(&snapshot).unwrap();
        let tool_ref = GeneratedToolRef {
            id: "discord-dm".into(),
            version: 1,
            fingerprint,
        };
        assert!(verify_tool_fingerprint(&tool_ref, &snapshot).is_ok());
        snapshot.program.push(AutomationStep::Wait { seconds: 0.1 });
        assert!(verify_tool_fingerprint(&tool_ref, &snapshot).is_err());
    }

    #[test]
    fn argument_digest_is_deterministic_and_sensitive_to_values() {
        let first = HashMap::from([
            ("message".into(), "Hello 👋\nnext line".into()),
            ("recipient".into(), "Alex".into()),
        ]);
        let second = HashMap::from([
            ("recipient".into(), "Alex".into()),
            ("message".into(), "Hello 👋\nnext line".into()),
        ]);
        assert_eq!(
            digest_resolved_arguments("fingerprint", &first),
            digest_resolved_arguments("fingerprint", &second)
        );
        let changed = HashMap::from([
            ("recipient".into(), "Alex".into()),
            ("message".into(), "Different".into()),
        ]);
        assert_ne!(
            digest_resolved_arguments("fingerprint", &first),
            digest_resolved_arguments("fingerprint", &changed)
        );
    }
}
