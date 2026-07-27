use crate::{macos, models::WorkflowNode};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::HashSet,
    fs,
    io::{Read, Write},
    net::TcpListener,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Default)]
pub struct SourceState {
    sms_after_row_id: Option<i64>,
}

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

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MessageRow {
    row_id: i64,
    guid: String,
    text: String,
    attributed_body_hex: String,
    message_date: i64,
    is_from_me: i64,
    service: String,
    sender: String,
    chat_identifier: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RowId {
    row_id: i64,
}

fn normalize_phone_number(value: &str) -> Result<String, String> {
    let mut digits = value
        .chars()
        .filter(char::is_ascii_digit)
        .collect::<String>();
    if digits.len() == 11 && digits.starts_with('1') {
        digits.remove(0);
    }
    if !(7..=15).contains(&digits.len()) {
        return Err("SMS phone number must contain 7 to 15 digits".into());
    }
    Ok(digits)
}

fn messages_database_path() -> Result<PathBuf, String> {
    let path = expand_home("~/Library/Messages/chat.db")?;
    fs::metadata(&path).map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => format!(
            "Swirl cannot read {}. Give Swirl Full Disk Access in System Settings > Privacy & Security > Full Disk Access, then restart it",
            path.display()
        ),
        std::io::ErrorKind::NotFound => format!(
            "Messages history was not found at {}. Sign in to Messages on this Mac first",
            path.display()
        ),
        _ => format!("Cannot access {}: {error}", path.display()),
    })?;
    Ok(path)
}

fn sqlite_json_query<T: for<'de> Deserialize<'de>>(
    database_path: &Path,
    query: &str,
) -> Result<Vec<T>, String> {
    let output = Command::new("/usr/bin/sqlite3")
        .args(["-readonly", "-json"])
        .arg(database_path)
        .arg(query)
        .output()
        .map_err(|error| format!("Cannot start the Messages database reader: {error}"))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if detail.to_ascii_lowercase().contains("authorization denied")
            || detail.to_ascii_lowercase().contains("permission denied")
        {
            return Err(
                "Swirl cannot read Messages. Give Swirl Full Disk Access in System Settings > Privacy & Security > Full Disk Access, then restart it"
                    .into(),
            );
        }
        return Err(format!("Messages database query failed: {detail}"));
    }
    if output.stdout.iter().all(u8::is_ascii_whitespace) {
        return Ok(Vec::new());
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("Messages database returned malformed data: {error}"))
}

fn phone_match_sql(column: &str, phone_number: &str) -> String {
    format!(
        "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE({column}, ''), '+', ''), '-', ''), '(', ''), ')', ''), ' ', '') LIKE '%{phone_number}'"
    )
}

fn latest_sms_row_id(database_path: &Path, phone_number: &str) -> Result<i64, String> {
    let chat_matches = phone_match_sql("c.chat_identifier", phone_number);
    let sender_matches = phone_match_sql("sender.id", phone_number);
    let participant_matches = phone_match_sql("participant.id", phone_number);
    let query = format!(
        "SELECT COALESCE(MAX(m.ROWID), 0) AS rowId
         FROM message m
         JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
         JOIN chat c ON c.ROWID = cmj.chat_id
         LEFT JOIN handle sender ON sender.ROWID = m.handle_id
         WHERE {chat_matches}
            OR {sender_matches}
            OR EXISTS (
                SELECT 1
                FROM chat_handle_join chj
                JOIN handle participant ON participant.ROWID = chj.handle_id
                WHERE chj.chat_id = c.ROWID AND {participant_matches}
            )"
    );
    Ok(sqlite_json_query::<RowId>(database_path, &query)?
        .first()
        .map(|row| row.row_id)
        .unwrap_or(0))
}

fn next_sms_message(
    database_path: &Path,
    phone_number: &str,
    after_row_id: i64,
) -> Result<Option<MessageRow>, String> {
    let chat_matches = phone_match_sql("c.chat_identifier", phone_number);
    let sender_matches = phone_match_sql("sender.id", phone_number);
    let participant_matches = phone_match_sql("participant.id", phone_number);
    let query = format!(
        "SELECT DISTINCT
             m.ROWID AS rowId,
             COALESCE(m.guid, '') AS guid,
             COALESCE(m.text, '') AS text,
             hex(COALESCE(m.attributedBody, x'')) AS attributedBodyHex,
             COALESCE(m.date, 0) AS messageDate,
             COALESCE(m.is_from_me, 0) AS isFromMe,
             COALESCE(m.service, '') AS service,
             COALESCE(sender.id, '') AS sender,
             COALESCE(c.chat_identifier, '') AS chatIdentifier
         FROM message m
         JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
         JOIN chat c ON c.ROWID = cmj.chat_id
         LEFT JOIN handle sender ON sender.ROWID = m.handle_id
         WHERE m.ROWID > {after_row_id}
           AND (
                {chat_matches}
                OR {sender_matches}
                OR EXISTS (
                    SELECT 1
                    FROM chat_handle_join chj
                    JOIN handle participant ON participant.ROWID = chj.handle_id
                    WHERE chj.chat_id = c.ROWID AND {participant_matches}
                )
           )
           AND (COALESCE(m.text, '') <> '' OR m.attributedBody IS NOT NULL)
         ORDER BY m.ROWID ASC
         LIMIT 1"
    );
    Ok(sqlite_json_query::<MessageRow>(database_path, &query)?
        .into_iter()
        .next())
}

fn decode_hex(value: &str) -> Result<Vec<u8>, String> {
    if !value.len().is_multiple_of(2) {
        return Err("Messages attributed body contained malformed hexadecimal data".into());
    }
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let encoded = std::str::from_utf8(pair).map_err(|error| error.to_string())?;
            u8::from_str_radix(encoded, 16).map_err(|error| error.to_string())
        })
        .collect()
}

fn plutil(blob: &[u8], arguments: &[&str]) -> Result<Vec<u8>, String> {
    let mut child = Command::new("/usr/bin/plutil")
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("Cannot start the Messages text decoder: {error}"))?;
    child
        .stdin
        .take()
        .ok_or_else(|| "Messages text decoder has no input stream".to_string())?
        .write_all(blob)
        .map_err(|error| error.to_string())?;
    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        Ok(output.stdout)
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn attributed_string_object_index(dump: &str) -> Option<usize> {
    dump.lines()
        .find(|line| line.contains("\"NSString\" =>") || line.contains("\"NS.string\" =>"))
        .and_then(|line| line.split("{value = ").nth(1))
        .and_then(|value| value.split('}').next())
        .and_then(|value| value.trim().parse::<usize>().ok())
}

fn decode_attributed_body(encoded: &str) -> Result<Option<String>, String> {
    if encoded.is_empty() {
        return Ok(None);
    }
    let blob = decode_hex(encoded)?;
    let dump = plutil(&blob, &["-p", "--", "-"])?;
    let dump = String::from_utf8_lossy(&dump);
    let Some(index) = attributed_string_object_index(&dump) else {
        return Ok(None);
    };
    let key_path = format!("$objects.{index}");
    let decoded = plutil(&blob, &["-extract", &key_path, "raw", "-o", "-", "--", "-"])?;
    let text = String::from_utf8_lossy(&decoded).trim().to_string();
    Ok((!text.is_empty()).then_some(text))
}

fn wait_for_sms(
    node: &WorkflowNode,
    cancelled: &AtomicBool,
    state: &mut SourceState,
) -> Result<Option<SourceEvent>, String> {
    let configured_number = string_config(node, "phoneNumber", "8604644276");
    let phone_number = normalize_phone_number(&configured_number)?;
    let interval = node
        .config
        .get("checkIntervalSec")
        .and_then(Value::as_u64)
        .unwrap_or(1)
        .clamp(1, 60);
    let database_path = messages_database_path()?;
    if state.sms_after_row_id.is_none() {
        state.sms_after_row_id = Some(latest_sms_row_id(&database_path, &phone_number)?);
    }
    println!(
        "[Swirl][Source] waiting for a new Messages text involving '{}'",
        phone_number
    );
    loop {
        if !sleep_interruptible(cancelled, Duration::from_secs(interval)) {
            return Ok(None);
        }
        let after_row_id = state.sms_after_row_id.unwrap_or(0);
        let Some(message) = next_sms_message(&database_path, &phone_number, after_row_id)? else {
            continue;
        };
        state.sms_after_row_id = Some(message.row_id);
        let body = if message.text.trim().is_empty() {
            decode_attributed_body(&message.attributed_body_hex)?
        } else {
            Some(message.text)
        };
        let Some(body) = body.filter(|value| !value.trim().is_empty()) else {
            continue;
        };
        return Ok(Some(SourceEvent {
            trigger_type: "trigger_sms".into(),
            timestamp_ms: now_ms(),
            payload: json!({
                "phoneNumber": phone_number,
                "messageGuid": message.guid,
                "messageDate": message.message_date,
                "isFromMe": message.is_from_me != 0,
                "direction": if message.is_from_me != 0 { "sent" } else { "received" },
                "service": message.service,
                "sender": message.sender,
                "chatIdentifier": message.chat_identifier,
                "text": body
            }),
            text: body,
        }));
    }
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
    state: &mut SourceState,
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
        "trigger_sms" => wait_for_sms(node, cancelled, state),
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

    #[test]
    fn phone_numbers_are_normalized_and_validated() {
        assert_eq!(
            normalize_phone_number("+1 (860) 464-4276").unwrap(),
            "8604644276"
        );
        assert!(normalize_phone_number("123").is_err());
    }

    #[test]
    fn attributed_messages_decode_to_plain_text() {
        let archive = "62706c6973743030d4010203040506070a582476657273696f6e592461726368697665725424746f7058246f626a6563747312000186a05f100f4e534b657965644172636869766572d1080954726f6f748001a60b0c13141a2055246e756c6cd30d0e0f101112584e53537472696e675624636c6173735c4e53417474726962757465738002800580035f100f68656c6c6f2073656c662074657874d315160e171819574e532e6b6579735a4e532e6f626a65637473a0a08004d21b1c1d1e5a24636c6173736e616d655824636c61737365735c4e5344696374696f6e617279a21d1f584e534f626a656374d21b1c21225f10124e5341747472696275746564537472696e67a2231f5f10124e5341747472696275746564537472696e6700080011001a00240029003200370049004c00510053005a0060006700700077008400860088008a009c00a300ab00b600b700b800ba00bf00ca00d300e000e300ec00f101060109000000000000020100000000000000240000000000000000000000000000011e";
        assert_eq!(
            decode_attributed_body(archive).unwrap().as_deref(),
            Some("hello self text")
        );
    }

    #[test]
    fn messages_query_filters_by_configured_phone_number() {
        let database_path = std::env::temp_dir().join(format!(
            "swirl-messages-{}-{}.db",
            std::process::id(),
            now_ms()
        ));
        let schema = "
            CREATE TABLE message (
                ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT,
                attributedBody BLOB, date INTEGER, is_from_me INTEGER,
                service TEXT, handle_id INTEGER
            );
            CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT);
            CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
            CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
            CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
            INSERT INTO handle VALUES (1, '+18604644276');
            INSERT INTO handle VALUES (2, '+14155550100');
            INSERT INTO chat VALUES (1, '+18604644276');
            INSERT INTO chat VALUES (2, '+14155550100');
            INSERT INTO message VALUES (10, 'match', 'run my workflow', NULL, 1, 1, 'iMessage', 1);
            INSERT INTO message VALUES (11, 'other', 'ignore me', NULL, 2, 1, 'iMessage', 2);
            INSERT INTO chat_message_join VALUES (1, 10);
            INSERT INTO chat_message_join VALUES (2, 11);
            INSERT INTO chat_handle_join VALUES (1, 1);
            INSERT INTO chat_handle_join VALUES (2, 2);
        ";
        let status = Command::new("/usr/bin/sqlite3")
            .arg(&database_path)
            .arg(schema)
            .status()
            .unwrap();
        assert!(status.success());

        assert_eq!(latest_sms_row_id(&database_path, "8604644276").unwrap(), 10);
        let message = next_sms_message(&database_path, "8604644276", 0)
            .unwrap()
            .unwrap();
        assert_eq!(message.guid, "match");
        assert_eq!(message.text, "run my workflow");

        fs::remove_file(database_path).unwrap();
    }
}
