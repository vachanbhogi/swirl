use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MacActionRequest {
    pub app: String,
    pub action: String,
    #[serde(default)]
    pub params: Value,
    #[serde(default)]
    pub approved: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MacActionResult {
    pub success: bool,
    pub output: Option<Value>,
    pub error: Option<String>,
    pub approval_required: bool,
    pub risk: String,
}

impl MacActionResult {
    fn success(output: Value, risk: &str) -> Self {
        Self {
            success: true,
            output: Some(output),
            error: None,
            approval_required: false,
            risk: risk.into(),
        }
    }

    fn failure(error: impl Into<String>, risk: &str) -> Self {
        Self {
            success: false,
            output: None,
            error: Some(error.into()),
            approval_required: false,
            risk: risk.into(),
        }
    }

    fn approval(reason: impl Into<String>, risk: &str) -> Self {
        Self {
            success: false,
            output: None,
            error: Some(reason.into()),
            approval_required: true,
            risk: risk.into(),
        }
    }
}

fn string_param(params: &Value, key: &str, fallback: &str) -> String {
    params
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_string()
}

fn applescript_string(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\r', "")
        .replace('\n', "\\n")
}

fn html_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
        .replace('\n', "<br>")
}

fn run_applescript(script: &str, risk: &str) -> MacActionResult {
    match run_applescript_stdout(script) {
        Ok(stdout) => MacActionResult::success(json!({ "stdout": stdout }), risk),
        Err(error) => MacActionResult::failure(error, risk),
    }
}

fn run_applescript_stdout(script: &str) -> Result<String, String> {
    match Command::new("osascript").arg("-e").arg(script).output() {
        Ok(output) if output.status.success() => {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        }
        Ok(output) => Err(String::from_utf8_lossy(&output.stderr).trim().to_string()),
        Err(error) => Err(error.to_string()),
    }
}

fn mail_snapshot(mailbox: &str) -> Result<std::collections::HashSet<String>, String> {
    let target = mail_target(mailbox);
    let script = format!(
        "tell application \"Mail\" to get id of every message of {target}"
    );
    let output = run_applescript_stdout(&script)?;
    Ok(output
        .split(',')
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(str::to_string)
        .collect())
}

fn mail_message_details(mailbox: &str, message_id: &str) -> Result<Value, String> {
    if !message_id.chars().all(|character| character.is_ascii_digit()) {
        return Err("Mail returned an invalid message identifier".into());
    }
    let target = mail_target(mailbox);
    let script = format!(
        "tell application \"Mail\"\nset m to first message of {target} whose id is {message_id}\nset AppleScript's text item delimiters to \"|||SWIRL|||\"\nreturn (subject of m as text) & \"|||SWIRL|||\" & (content of m as text) & \"|||SWIRL|||\" & (sender of m as text)\nend tell"
    );
    let output = run_applescript_stdout(&script)?;
    let mut parts = output.splitn(3, "|||SWIRL|||");
    Ok(json!({
        "subject": parts.next().unwrap_or_default(),
        "content": parts.next().unwrap_or_default(),
        "sender": parts.next().unwrap_or_default(),
        "messageId": message_id
    }))
}

fn mail_target(mailbox: &str) -> String {
    if mailbox.trim().eq_ignore_ascii_case("inbox") {
        "inbox".into()
    } else {
        format!("mailbox \"{}\"", applescript_string(mailbox))
    }
}

fn wait_for_new_email(params: &Value, risk: &str) -> MacActionResult {
    let mailbox = string_param(params, "mailbox", "Inbox");
    let filter = string_param(params, "filterSubject", "").to_ascii_lowercase();
    let interval = params
        .get("checkIntervalSec")
        .and_then(Value::as_u64)
        .unwrap_or(15)
        .clamp(1, 3600);
    let timeout = params
        .get("waitTimeoutSec")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let baseline = match mail_snapshot(&mailbox) {
        Ok(ids) => ids,
        Err(error) => return MacActionResult::failure(error, risk),
    };
    println!(
        "[Swirl][Source] waiting for a new email in '{}' (filter: {})",
        mailbox,
        if filter.is_empty() { "none" } else { &filter }
    );
    let started = std::time::Instant::now();
    loop {
        std::thread::sleep(std::time::Duration::from_secs(interval));
        let current = match mail_snapshot(&mailbox) {
            Ok(ids) => ids,
            Err(error) => return MacActionResult::failure(error, risk),
        };
        for id in current.difference(&baseline) {
            let details = match mail_message_details(&mailbox, id) {
                Ok(details) => details,
                Err(_) => continue,
            };
            let subject = details
                .get("subject")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !filter.is_empty() && !subject.to_ascii_lowercase().contains(&filter) {
                continue;
            }
            println!("[Swirl][Source] new email received: {}", subject);
            return MacActionResult::success(details, risk);
        }
        if timeout > 0 && started.elapsed().as_secs() >= timeout {
            return MacActionResult::failure(
                format!("Timed out waiting for a matching email after {timeout} seconds"),
                risk,
            );
        }
    }
}

fn expand_home(value: &str) -> Result<PathBuf, String> {
    if value == "~" || value.starts_with("~/") {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| "HOME is not available".to_string())?;
        return Ok(if value == "~" {
            home
        } else {
            home.join(&value[2..])
        });
    }
    Ok(PathBuf::from(value))
}

fn organize_by_extension(target: &Path) -> Result<Value, String> {
    if !target.is_dir() {
        return Err(format!(
            "Target directory does not exist: {}",
            target.display()
        ));
    }
    let mut moved = Vec::new();
    for entry in fs::read_dir(target).map_err(|error| error.to_string())? {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        if !path.is_file()
            || path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with('.'))
        {
            continue;
        }
        let extension = path
            .extension()
            .and_then(|extension| extension.to_str())
            .filter(|extension| !extension.is_empty())
            .map(|extension| extension.to_ascii_uppercase())
            .unwrap_or_else(|| "MISC".to_string());
        let destination_dir = target.join(format!("{extension}_Files"));
        fs::create_dir_all(&destination_dir).map_err(|error| error.to_string())?;
        let destination = destination_dir.join(
            path.file_name()
                .ok_or_else(|| "File name could not be resolved".to_string())?,
        );
        if destination.exists() {
            return Err(format!(
                "Refusing to overwrite existing file: {}",
                destination.display()
            ));
        }
        fs::rename(&path, &destination).map_err(|error| error.to_string())?;
        moved.push(json!({
            "from": path.to_string_lossy(),
            "to": destination.to_string_lossy()
        }));
    }
    Ok(json!({ "organizedCount": moved.len(), "moved": moved }))
}

pub fn execute(request: &MacActionRequest) -> MacActionResult {
    let app = request.app.trim().to_ascii_lowercase();
    let action = request.action.trim().to_ascii_lowercase();
    let key = format!("{app}:{action}");
    let high_risk = matches!(
        key.as_str(),
        "finder:move"
            | "finder:organize_by_extension"
            | "terminal:exec_shell"
            | "system:exec_shell"
    );
    let medium_risk = matches!(key.as_str(), "calendar:create_event");
    let risk = if high_risk {
        "high"
    } else if medium_risk {
        "medium"
    } else {
        "low"
    };
    if (high_risk || medium_risk) && !request.approved {
        return MacActionResult::approval(
            format!(
                "Approval is required before executing {}/{}",
                request.app, request.action
            ),
            risk,
        );
    }

    match (app.as_str(), action.as_str()) {
        ("notes", "create_note") => {
            let title = string_param(&request.params, "title", &string_param(&request.params, "defaultTitle", "Swirl Workflow Note"));
            let content = string_param(&request.params, "content", "Generated by Swirl Jac Walker");
            let folder = string_param(&request.params, "folder", "Swirl Automations");
            let script = format!(
                "tell application \"Notes\"\n\
                 tell default account\n\
                 if not (exists folder \"{}\") then make new folder with properties {{name:\"{}\"}}\n\
                 make new note at folder \"{}\" with properties {{name:\"{}\", body:\"<h1>{}</h1><p>{}</p>\"}}\n\
                 end tell\nend tell",
                applescript_string(&folder),
                applescript_string(&folder),
                applescript_string(&folder),
                applescript_string(&title),
                applescript_string(&html_text(&title)),
                applescript_string(&html_text(&content)),
            );
            run_applescript(&script, risk)
        }
        ("notes", "append_note") => {
            let title = string_param(&request.params, "title", "Swirl Workflow Note");
            let content = string_param(&request.params, "content", "");
            let script = format!(
                "tell application \"Notes\" to tell default account to set body of first note whose name is \"{}\" to (body of first note whose name is \"{}\") & \"<br>{}\"",
                applescript_string(&title),
                applescript_string(&title),
                applescript_string(&html_text(&content)),
            );
            run_applescript(&script, risk)
        }
        ("notes", "search_notes") => {
            let query = string_param(&request.params, "query", "");
            let script = format!(
                "tell application \"Notes\" to tell default account to get name of every note whose name contains \"{}\"",
                applescript_string(&query)
            );
            run_applescript(&script, risk)
        }
        ("system", "display_notification") => {
            let text = string_param(&request.params, "text", "Swirl task completed");
            let title = string_param(&request.params, "title", "Swirl Desktop Agent");
            let sound = string_param(&request.params, "sound", "Glass");
            run_applescript(
                &format!(
                    "display notification \"{}\" with title \"{}\" sound name \"{}\"",
                    applescript_string(&text),
                    applescript_string(&title),
                    applescript_string(&sound),
                ),
                risk,
            )
        }
        ("system", "set_volume") => {
            let volume = request
                .params
                .get("volume")
                .and_then(Value::as_i64)
                .unwrap_or(50)
                .clamp(0, 100);
            run_applescript(&format!("set volume output volume {volume}"), risk)
        }
        ("finder", "list_files") => {
            let target = expand_home(&string_param(&request.params, "targetDirectory", "~/Desktop"));
            match target.and_then(|path| {
                fs::read_dir(path)
                    .map_err(|error| error.to_string())?
                    .map(|entry| {
                        entry
                            .map(|item| item.file_name().to_string_lossy().to_string())
                            .map_err(|error| error.to_string())
                    })
                    .collect::<Result<Vec<_>, _>>()
            }) {
                Ok(files) => MacActionResult::success(json!({ "files": files }), risk),
                Err(error) => MacActionResult::failure(error, risk),
            }
        }
        ("finder", "create_folder") => {
            let target = expand_home(&string_param(&request.params, "path", "~/Desktop/Swirl"));
            match target.and_then(|path| {
                fs::create_dir_all(&path)
                    .map(|_| json!({ "path": path.to_string_lossy() }))
                    .map_err(|error| error.to_string())
            }) {
                Ok(output) => MacActionResult::success(output, risk),
                Err(error) => MacActionResult::failure(error, risk),
            }
        }
        ("finder", "organize_by_extension") => {
            let target = expand_home(&string_param(&request.params, "targetDirectory", "~/Desktop"));
            match target.and_then(|path| organize_by_extension(&path)) {
                Ok(output) => MacActionResult::success(output, risk),
                Err(error) => MacActionResult::failure(error, risk),
            }
        }
        ("finder", "move") => {
            let source = expand_home(&string_param(&request.params, "source", ""));
            let destination = expand_home(&string_param(&request.params, "destination", ""));
            match source.and_then(|source| {
                destination.and_then(|destination| {
                    if !source.exists() {
                        return Err(format!("Source does not exist: {}", source.display()));
                    }
                    if destination.exists() {
                        return Err(format!(
                            "Refusing to overwrite existing path: {}",
                            destination.display()
                        ));
                    }
                    if let Some(parent) = destination.parent() {
                        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
                    }
                    fs::rename(&source, &destination).map_err(|error| error.to_string())?;
                    Ok(json!({
                        "from": source.to_string_lossy(),
                        "to": destination.to_string_lossy()
                    }))
                })
            }) {
                Ok(output) => MacActionResult::success(output, risk),
                Err(error) => MacActionResult::failure(error, risk),
            }
        }
        ("mail", "create_draft") => {
            let recipient = string_param(&request.params, "to", "");
            let subject = string_param(&request.params, "subject", "Swirl Draft");
            let content = string_param(&request.params, "content", "");
            let script = format!(
                "tell application \"Mail\"\nset m to make new outgoing message with properties {{subject:\"{}\", content:\"{}\", visible:true}}\ntell m to make new to recipient with properties {{address:\"{}\"}}\nend tell",
                applescript_string(&subject),
                applescript_string(&content),
                applescript_string(&recipient),
            );
            run_applescript(&script, risk)
        }
        ("mail", "recent_messages") => {
            let limit = request
                .params
                .get("limit")
                .and_then(Value::as_u64)
                .unwrap_or(10)
                .clamp(1, 50);
            run_applescript(
                &format!(
                    "tell application \"Mail\" to get subject of messages 1 thru {limit} of inbox"
                ),
                risk,
            )
        }
        ("mail", "wait_for_new_message") => wait_for_new_email(&request.params, risk),
        ("calendar", "create_event") => {
            let title = string_param(&request.params, "title", "Swirl Event");
            let start = string_param(&request.params, "start", "");
            let end = string_param(&request.params, "end", "");
            let calendar = string_param(&request.params, "calendar", "Calendar");
            let script = format!(
                "tell application \"Calendar\" to tell calendar \"{}\" to make new event with properties {{summary:\"{}\", start date:date \"{}\", end date:date \"{}\"}}",
                applescript_string(&calendar),
                applescript_string(&title),
                applescript_string(&start),
                applescript_string(&end),
            );
            run_applescript(&script, risk)
        }
        ("calendar", "list_events") => run_applescript(
            "tell application \"Calendar\" to get summary of every event of every calendar whose start date is greater than (current date)",
            risk,
        ),
        ("terminal", "exec_shell") | ("system", "exec_shell") => {
            let command = string_param(&request.params, "command", "");
            if command.is_empty() || command.len() > 4096 {
                return MacActionResult::failure("Shell command must be 1-4096 characters", risk);
            }
            match Command::new("/bin/zsh").arg("-c").arg(&command).output() {
                Ok(output) => MacActionResult {
                    success: output.status.success(),
                    output: Some(json!({
                        "stdout": String::from_utf8_lossy(&output.stdout).trim(),
                        "exitCode": output.status.code()
                    })),
                    error: (!output.stderr.is_empty())
                        .then(|| String::from_utf8_lossy(&output.stderr).trim().to_string()),
                    approval_required: false,
                    risk: risk.into(),
                },
                Err(error) => MacActionResult::failure(error.to_string(), risk),
            }
        }
        _ => MacActionResult::failure(
            format!("Unsupported macOS action: {}/{}", request.app, request.action),
            risk,
        ),
    }
}

pub fn execute_restricted_applescript(script: &str) -> MacActionResult {
    let lowered = script.to_ascii_lowercase();
    let allowed = (lowered.contains("tell application \"notes\"")
        || lowered.contains("display notification"))
        && ![
            "do shell script",
            "delete ",
            "keystroke",
            "tell application \"terminal\"",
        ]
        .iter()
        .any(|token| lowered.contains(token));
    if !allowed || script.len() > 16_000 {
        return MacActionResult::failure(
            "Raw AppleScript is restricted; use execute_mac_action for typed operations",
            "high",
        );
    }
    run_applescript(script, "low")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn high_risk_action_requires_approval() {
        let result = execute(&MacActionRequest {
            app: "Finder".into(),
            action: "organize_by_extension".into(),
            params: json!({ "targetDirectory": "/tmp" }),
            approved: false,
        });
        assert!(!result.success);
        assert!(result.approval_required);
        assert_eq!(result.risk, "high");
    }

    #[test]
    fn raw_applescript_rejects_shell_escape() {
        let result = execute_restricted_applescript(
            "tell application \"Notes\" to do shell script \"whoami\"",
        );
        assert!(!result.success);
        assert_eq!(result.risk, "high");
    }
}
