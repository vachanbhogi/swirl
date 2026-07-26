use crate::{macos, models::WorkflowNode};
use serde_json::{json, Value};
use std::{
    collections::HashSet,
    fs,
    io::{Read, Write},
    net::TcpListener,
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone)]
pub struct SourceEvent {
    pub trigger_type: String,
    pub timestamp_ms: u64,
    pub payload: Value,
    pub text: String,
}

impl SourceEvent {
    pub fn output(&self) -> Value {
        json!({
            "status": "triggered",
            "triggerType": self.trigger_type,
            "triggerTimestamp": self.timestamp_ms,
            "payload": self.payload
        })
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn string_config(node: &WorkflowNode, key: &str, fallback: &str) -> String {
    node.config
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_string()
}

fn sleep_interruptible(cancelled: &AtomicBool, duration: Duration) -> bool {
    let step = Duration::from_millis(100);
    let mut elapsed = Duration::ZERO;
    while elapsed < duration {
        if cancelled.load(Ordering::Relaxed) {
            return false;
        }
        let remaining = duration.saturating_sub(elapsed);
        let current = remaining.min(step);
        std::thread::sleep(current);
        elapsed += current;
    }
    !cancelled.load(Ordering::Relaxed)
}

fn expand_home(value: &str) -> Result<PathBuf, String> {
    if value == "~" || value.starts_with("~/") {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| "HOME is unavailable".to_string())?;
        return Ok(if value == "~" {
            home
        } else {
            home.join(&value[2..])
        });
    }
    Ok(PathBuf::from(value))
}

fn directory_files(path: &Path) -> Result<HashSet<PathBuf>, String> {
    if !path.is_dir() {
        return Err(format!("Watched folder does not exist: {}", path.display()));
    }
    Ok(fs::read_dir(path)
        .map_err(|error| error.to_string())?
        .filter_map(|entry| entry.ok().map(|item| item.path()))
        .filter(|item| item.is_file())
        .collect::<HashSet<_>>())
}

fn matches_file_pattern(path: &Path, pattern: &str) -> bool {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("");
    if pattern.is_empty() || pattern == "*" {
        return true;
    }
    if let Some(extension) = pattern.strip_prefix("*.") {
        return path.extension().and_then(|value| value.to_str()) == Some(extension);
    }
    name == pattern
}

fn wait_for_file(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let watch_path = expand_home(&string_config(node, "watchPath", "~/Downloads"))?;
    let pattern = string_config(node, "filePattern", "*");
    let interval = node
        .config
        .get("checkIntervalSec")
        .and_then(Value::as_u64)
        .unwrap_or(2)
        .clamp(1, 60);
    let baseline = directory_files(&watch_path)?;
    println!(
        "[Swirl][Source] watching '{}' for new files matching '{}'",
        watch_path.display(),
        pattern
    );
    loop {
        if !sleep_interruptible(cancelled, Duration::from_secs(interval)) {
            return Ok(None);
        }
        let current = directory_files(&watch_path)?;
        if let Some(path) = current
            .difference(&baseline)
            .find(|path| matches_file_pattern(path, &pattern))
        {
            let file_name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("")
                .to_string();
            let file_ext = path
                .extension()
                .and_then(|value| value.to_str())
                .unwrap_or("")
                .to_string();
            let path_text = path.to_string_lossy().to_string();
            return Ok(Some(SourceEvent {
                trigger_type: "trigger_file".into(),
                timestamp_ms: now_ms(),
                payload: json!({
                    "filePath": path_text,
                    "fileName": file_name,
                    "fileExt": file_ext
                }),
                text: path.to_string_lossy().to_string(),
            }));
        }
    }
}

fn clipboard_text() -> Result<String, String> {
    let output = Command::new("pbpaste")
        .output()
        .map_err(|error| format!("Cannot read the macOS clipboard: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn wait_for_clipboard(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let baseline = clipboard_text()?;
    let min_chars = node
        .config
        .get("minChars")
        .and_then(Value::as_u64)
        .unwrap_or(1) as usize;
    let interval = node
        .config
        .get("checkIntervalSec")
        .and_then(Value::as_u64)
        .unwrap_or(1)
        .clamp(1, 60);
    println!("[Swirl][Source] waiting for new clipboard text");
    loop {
        if !sleep_interruptible(cancelled, Duration::from_secs(interval)) {
            return Ok(None);
        }
        let current = clipboard_text()?;
        if current != baseline && current.chars().count() >= min_chars {
            return Ok(Some(SourceEvent {
                trigger_type: "trigger_clipboard".into(),
                timestamp_ms: now_ms(),
                payload: json!({
                    "clipboardText": current,
                    "contentType": "text/plain"
                }),
                text: current,
            }));
        }
    }
}

fn cron_field_matches(field: &str, value: u32) -> bool {
    field.split(',').any(|part| {
        let part = part.trim();
        if part == "*" {
            return true;
        }
        if let Some(step) = part
            .strip_prefix("*/")
            .and_then(|raw| raw.parse::<u32>().ok())
        {
            return step > 0 && value.is_multiple_of(step);
        }
        part.parse::<u32>() == Ok(value)
    })
}

fn cron_snapshot(timezone: &str) -> Result<(String, [u32; 5]), String> {
    let output = Command::new("date")
        .env("TZ", timezone)
        .arg("+%Y-%m-%dT%H:%M|%M|%H|%d|%m|%w")
        .output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let mut parts = text.split('|');
    let key = parts.next().unwrap_or_default().to_string();
    let values = [
        parts.next().unwrap_or("0").parse().unwrap_or(0),
        parts.next().unwrap_or("0").parse().unwrap_or(0),
        parts.next().unwrap_or("0").parse().unwrap_or(0),
        parts.next().unwrap_or("0").parse().unwrap_or(0),
        parts.next().unwrap_or("0").parse().unwrap_or(0),
    ];
    Ok((key, values))
}

fn wait_for_cron(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let expression = string_config(node, "cron", "*/15 * * * *");
    let fields = expression.split_whitespace().collect::<Vec<_>>();
    if fields.len() != 5 {
        return Err("Cron schedule must contain five fields".into());
    }
    let timezone = string_config(node, "timezone", "America/Los_Angeles");
    let (initial_key, _) = cron_snapshot(&timezone)?;
    println!(
        "[Swirl][Source] armed cron '{}' in timezone '{}'",
        expression, timezone
    );
    loop {
        if !sleep_interruptible(cancelled, Duration::from_secs(1)) {
            return Ok(None);
        }
        let (key, values) = cron_snapshot(&timezone)?;
        if key != initial_key
            && cron_field_matches(fields[0], values[0])
            && cron_field_matches(fields[1], values[1])
            && cron_field_matches(fields[2], values[2])
            && cron_field_matches(fields[3], values[3])
            && cron_field_matches(fields[4], values[4])
        {
            return Ok(Some(SourceEvent {
                trigger_type: "trigger_cron".into(),
                timestamp_ms: now_ms(),
                payload: json!({
                    "cron": expression,
                    "timezone": timezone,
                    "scheduledAt": key
                }),
                text: key,
            }));
        }
    }
}

fn wait_for_email(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let result = macos::wait_for_new_email_cancellable(&node.config, "low", cancelled);
    if cancelled.load(Ordering::Relaxed) {
        return Ok(None);
    }
    if !result.success {
        return Err(result
            .error
            .unwrap_or_else(|| "Apple Mail trigger failed".into()));
    }
    let email = result.output.unwrap_or(Value::Null);
    let text = email
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    Ok(Some(SourceEvent {
        trigger_type: "trigger_email".into(),
        timestamp_ms: now_ms(),
        payload: email,
        text,
    }))
}

fn wait_for_voice(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let endpoint = std::env::var("SWIRL_WHISPER_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8765/v1/events/next".into());
    if !(endpoint.starts_with("http://127.0.0.1") || endpoint.starts_with("http://localhost")) {
        return Err("SWIRL_WHISPER_URL must use a localhost HTTP endpoint".into());
    }
    let timeout = node
        .config
        .get("listenTimeoutSec")
        .and_then(Value::as_u64)
        .unwrap_or(30)
        .clamp(1, 60);
    println!("[Swirl][Source] waiting for local Whisper at '{endpoint}'");
    while !cancelled.load(Ordering::Relaxed) {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(timeout + 5))
            .build()
            .map_err(|error| error.to_string())?;
        let response = client
            .post(&endpoint)
            .json(&json!({
                "wakeWord": string_config(node, "wakeWord", "Hey Swirl"),
                "language": string_config(node, "language", "en-US"),
                "timeoutSec": timeout
            }))
            .send()
            .map_err(|error| {
                format!(
                    "Local Whisper is unavailable at {endpoint}. Start the service or set SWIRL_WHISPER_URL: {error}"
                )
            })?;
        if response.status().as_u16() == 204 || response.status().as_u16() == 408 {
            continue;
        }
        if !response.status().is_success() {
            return Err(format!("Local Whisper returned HTTP {}", response.status()));
        }
        let payload: Value = response.json().map_err(|error| error.to_string())?;
        let transcript = payload
            .get("transcript")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        if !transcript.is_empty() {
            return Ok(Some(SourceEvent {
                trigger_type: "trigger_voice".into(),
                timestamp_ms: payload
                    .get("timestampMs")
                    .and_then(Value::as_u64)
                    .unwrap_or_else(now_ms),
                payload,
                text: transcript,
            }));
        }
    }
    Ok(None)
}

type ParsedHttpRequest = (String, String, Vec<(String, String)>, String);

fn parse_http_request(bytes: &[u8]) -> Result<ParsedHttpRequest, String> {
    let request = String::from_utf8_lossy(bytes);
    let (head, body) = request.split_once("\r\n\r\n").unwrap_or((&request, ""));
    let mut lines = head.lines();
    let request_line = lines
        .next()
        .ok_or_else(|| "Empty webhook request".to_string())?;
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_string();
    let path = request_parts.next().unwrap_or_default().to_string();
    let headers = lines
        .filter_map(|line| line.split_once(':'))
        .map(|(key, value)| (key.trim().to_ascii_lowercase(), value.trim().to_string()))
        .collect();
    Ok((method, path, headers, body.to_string()))
}

fn wait_for_webhook(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    let port = node
        .config
        .get("port")
        .and_then(Value::as_u64)
        .unwrap_or(8787)
        .clamp(1024, 65535) as u16;
    let expected_path = string_config(node, "path", "/api/v1/webhook");
    let expected_method = string_config(node, "method", "POST").to_ascii_uppercase();
    let listener = TcpListener::bind(("127.0.0.1", port))
        .map_err(|error| format!("Cannot arm localhost webhook on port {port}: {error}"))?;
    listener
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    println!("[Swirl][Source] webhook armed at http://127.0.0.1:{port}{expected_path}");
    while !cancelled.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((mut stream, _)) => {
                let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
                let mut buffer = vec![0_u8; 1_048_576];
                let size = stream
                    .read(&mut buffer)
                    .map_err(|error| error.to_string())?;
                let (method, path, headers, body) = parse_http_request(&buffer[..size])?;
                let authorized = if node
                    .config
                    .get("authRequired")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    let expected = string_config(node, "authToken", "");
                    headers.iter().any(|(key, value)| {
                        key == "authorization" && value == &format!("Bearer {expected}")
                    }) && !expected.is_empty()
                } else {
                    true
                };
                if method != expected_method || path != expected_path || !authorized {
                    let status = if !authorized {
                        "401 Unauthorized"
                    } else {
                        "404 Not Found"
                    };
                    let _ = stream.write_all(
                        format!("HTTP/1.1 {status}\r\nContent-Length: 0\r\n\r\n").as_bytes(),
                    );
                    continue;
                }
                let payload = serde_json::from_str::<Value>(&body)
                    .unwrap_or_else(|_| json!({ "body": body }));
                let response = b"{\"accepted\":true}";
                let _ = stream.write_all(
                    format!(
                        "HTTP/1.1 202 Accepted\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n",
                        response.len()
                    )
                    .as_bytes(),
                );
                let _ = stream.write_all(response);
                return Ok(Some(SourceEvent {
                    trigger_type: "trigger_webhook".into(),
                    timestamp_ms: now_ms(),
                    text: payload.to_string(),
                    payload: json!({ "body": payload, "headers": headers }),
                }));
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                if !sleep_interruptible(cancelled, Duration::from_millis(100)) {
                    return Ok(None);
                }
            }
            Err(error) => return Err(error.to_string()),
        }
    }
    Ok(None)
}

pub fn wait_for_source(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
) -> Result<Option<SourceEvent>, String> {
    match node
        .config
        .get("eventType")
        .and_then(Value::as_str)
        .unwrap_or("trigger_email")
    {
        "trigger_email" => wait_for_email(node, cancelled),
        "trigger_file" => wait_for_file(node, cancelled),
        "trigger_cron" => wait_for_cron(node, cancelled),
        "trigger_clipboard" => wait_for_clipboard(node, cancelled),
        "trigger_webhook" => wait_for_webhook(node, cancelled),
        "trigger_voice" => wait_for_voice(node, cancelled),
        event_type => Err(format!("Unsupported Source event type: {event_type}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_patterns_match_expected_names() {
        assert!(matches_file_pattern(Path::new("/tmp/report.pdf"), "*"));
        assert!(matches_file_pattern(Path::new("/tmp/report.pdf"), "*.pdf"));
        assert!(!matches_file_pattern(Path::new("/tmp/report.txt"), "*.pdf"));
    }

    #[test]
    fn cron_fields_support_wildcards_steps_and_values() {
        assert!(cron_field_matches("*", 13));
        assert!(cron_field_matches("*/5", 15));
        assert!(!cron_field_matches("*/5", 14));
        assert!(cron_field_matches("1,7,12", 7));
    }

    #[test]
    fn webhook_parser_extracts_json_body() {
        let request = b"POST /hook HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"ok\":true}";
        let (method, path, _, body) = parse_http_request(request).unwrap();
        assert_eq!(method, "POST");
        assert_eq!(path, "/hook");
        assert_eq!(body, "{\"ok\":true}");
    }
}
