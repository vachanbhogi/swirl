use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, ChildStdin, Command, Stdio},
    sync::{mpsc, Mutex},
    thread,
    time::Duration,
};
use tauri::{AppHandle, Manager};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServerConfig {
    pub name: String,
    pub transport: String,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub url: Option<String>,
    #[serde(default)]
    pub env: HashMap<String, String>,
}

impl McpServerConfig {
    fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty()
            || self.name.len() > 80
            || !self.name.chars().all(|character| {
                character.is_ascii_alphanumeric() || matches!(character, '-' | '_')
            })
        {
            return Err("MCP server name must use 1-80 letters, numbers, - or _".into());
        }
        match self.transport.as_str() {
            "stdio"
                if self
                    .command
                    .as_deref()
                    .is_some_and(|value| !value.trim().is_empty()) =>
            {
                Ok(())
            }
            "http"
                if self.url.as_deref().is_some_and(|url| {
                    url.starts_with("https://")
                        || url.starts_with("http://127.0.0.1")
                        || url.starts_with("http://localhost")
                }) =>
            {
                Ok(())
            }
            "stdio" => Err("stdio MCP servers require a command".into()),
            "http" => Err("HTTP MCP URLs must use HTTPS or local loopback HTTP".into()),
            _ => Err("MCP transport must be stdio or http".into()),
        }
    }
}

struct McpSession {
    child: Child,
    stdin: ChildStdin,
    messages: mpsc::Receiver<Value>,
    reader_thread: Option<thread::JoinHandle<()>>,
    initialized: bool,
}

impl McpSession {
    fn stop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        if let Some(reader) = self.reader_thread.take() {
            let _ = reader.join();
        }
    }
}

pub struct McpManager {
    configs: HashMap<String, McpServerConfig>,
    sessions: HashMap<String, McpSession>,
    http_sessions: HashMap<String, Option<String>>,
    config_path: PathBuf,
    next_id: u64,
}

pub struct McpState(pub Mutex<McpManager>);

impl McpManager {
    pub fn load(app: &AppHandle) -> Self {
        let config_dir = app
            .path()
            .app_data_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join("mcp");
        let _ = fs::create_dir_all(&config_dir);
        let config_path = config_dir.join("servers.json");
        let configs = fs::read(&config_path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Vec<McpServerConfig>>(&bytes).ok())
            .unwrap_or_default()
            .into_iter()
            .map(|config| (config.name.clone(), config))
            .collect();
        Self {
            configs,
            sessions: HashMap::new(),
            http_sessions: HashMap::new(),
            config_path,
            next_id: 1,
        }
    }

    fn save(&self) -> Result<(), String> {
        let mut configs: Vec<&McpServerConfig> = self.configs.values().collect();
        configs.sort_by_key(|config| &config.name);
        let bytes = serde_json::to_vec_pretty(&configs).map_err(|error| error.to_string())?;
        let temporary = self.config_path.with_extension("tmp");
        fs::write(&temporary, bytes).map_err(|error| error.to_string())?;
        fs::rename(&temporary, &self.config_path).map_err(|error| error.to_string())
    }

    pub fn register(&mut self, config: McpServerConfig) -> Result<(), String> {
        config.validate()?;
        if let Some(mut session) = self.sessions.remove(&config.name) {
            session.stop();
        }
        self.http_sessions.remove(&config.name);
        self.configs.insert(config.name.clone(), config);
        self.save()
    }

    pub fn remove(&mut self, name: &str) -> Result<bool, String> {
        if let Some(mut session) = self.sessions.remove(name) {
            session.stop();
        }
        self.http_sessions.remove(name);
        let removed = self.configs.remove(name).is_some();
        self.save()?;
        Ok(removed)
    }

    pub fn configs(&self) -> Vec<McpServerConfig> {
        let mut configs: Vec<_> = self.configs.values().cloned().collect();
        configs.sort_by(|left, right| left.name.cmp(&right.name));
        configs
    }

    fn id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    fn spawn_session(config: &McpServerConfig) -> Result<McpSession, String> {
        let mut command = Command::new(
            config
                .command
                .as_deref()
                .ok_or_else(|| "stdio MCP command is missing".to_string())?,
        );
        command
            .args(&config.args)
            .envs(&config.env)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        let mut child = command
            .spawn()
            .map_err(|error| format!("Cannot start MCP server {}: {error}", config.name))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "MCP stdin was not available".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "MCP stdout was not available".to_string())?;
        let (sender, messages) = mpsc::channel();
        let reader_thread = thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                let Ok(line) = line else {
                    break;
                };
                if let Ok(message) = serde_json::from_str::<Value>(line.trim()) {
                    if sender.send(message).is_err() {
                        break;
                    }
                }
            }
        });
        Ok(McpSession {
            child,
            stdin,
            messages,
            reader_thread: Some(reader_thread),
            initialized: false,
        })
    }

    fn stdio_rpc(session: &mut McpSession, request: &Value) -> Result<Value, String> {
        let expected_id = request.get("id").cloned();
        serde_json::to_writer(&mut session.stdin, request).map_err(|error| error.to_string())?;
        session
            .stdin
            .write_all(b"\n")
            .and_then(|_| session.stdin.flush())
            .map_err(|error| error.to_string())?;

        for _ in 0..500 {
            let message = session
                .messages
                .recv_timeout(Duration::from_secs(15))
                .map_err(|error| format!("Timed out waiting for MCP response: {error}"))?;
            if message.get("id") == expected_id.as_ref() {
                if let Some(error) = message.get("error") {
                    return Err(format!("MCP error response: {error}"));
                }
                return Ok(message.get("result").cloned().unwrap_or(Value::Null));
            }
        }
        Err("MCP response limit exceeded".into())
    }

    fn http_rpc(
        config: &McpServerConfig,
        request: &Value,
        session_id: Option<&str>,
    ) -> Result<(Value, Option<String>), String> {
        let client = reqwest::blocking::Client::new();
        let mut builder = client
            .post(
                config
                    .url
                    .as_deref()
                    .ok_or_else(|| "HTTP MCP URL is missing".to_string())?,
            )
            .header("MCP-Protocol-Version", "2025-06-18")
            .header("Accept", "application/json, text/event-stream")
            .json(request);
        if let Some(session_id) = session_id {
            builder = builder.header("Mcp-Session-Id", session_id);
        }
        let response = builder.send().map_err(|error| error.to_string())?;
        if !response.status().is_success() {
            return Err(format!("MCP HTTP status {}", response.status()));
        }
        let next_session_id = response
            .headers()
            .get("Mcp-Session-Id")
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let message: Value = response.json().map_err(|error| error.to_string())?;
        if let Some(error) = message.get("error") {
            return Err(format!("MCP error response: {error}"));
        }
        Ok((
            message.get("result").cloned().unwrap_or(Value::Null),
            next_session_id,
        ))
    }

    fn http_notification(
        config: &McpServerConfig,
        notification: &Value,
        session_id: Option<&str>,
    ) -> Result<(), String> {
        let client = reqwest::blocking::Client::new();
        let mut builder = client
            .post(
                config
                    .url
                    .as_deref()
                    .ok_or_else(|| "HTTP MCP URL is missing".to_string())?,
            )
            .header("MCP-Protocol-Version", "2025-06-18")
            .header("Accept", "application/json, text/event-stream")
            .json(notification);
        if let Some(session_id) = session_id {
            builder = builder.header("Mcp-Session-Id", session_id);
        }
        let response = builder.send().map_err(|error| error.to_string())?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(format!("MCP HTTP status {}", response.status()))
        }
    }

    fn ensure_initialized(&mut self, name: &str) -> Result<(), String> {
        let config = self
            .configs
            .get(name)
            .cloned()
            .ok_or_else(|| format!("Unknown MCP server: {name}"))?;
        if config.transport == "http" {
            if self.http_sessions.contains_key(name) {
                return Ok(());
            }
            let request = json!({
                "jsonrpc": "2.0",
                "id": self.id(),
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": { "name": "swirl", "version": env!("CARGO_PKG_VERSION") }
                }
            });
            let (_, session_id) = Self::http_rpc(&config, &request, None)?;
            Self::http_notification(
                &config,
                &json!({
                    "jsonrpc": "2.0",
                    "method": "notifications/initialized",
                    "params": {}
                }),
                session_id.as_deref(),
            )?;
            self.http_sessions.insert(name.to_string(), session_id);
            return Ok(());
        }
        if !self.sessions.contains_key(name) {
            self.sessions
                .insert(name.to_string(), Self::spawn_session(&config)?);
        }
        if self
            .sessions
            .get(name)
            .is_some_and(|session| session.initialized)
        {
            return Ok(());
        }
        let request_id = self.id();
        let request = json!({
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": { "name": "swirl", "version": env!("CARGO_PKG_VERSION") }
            }
        });
        let session = self.sessions.get_mut(name).expect("session created");
        Self::stdio_rpc(session, &request)?;
        let notification = json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {}
        });
        serde_json::to_writer(&mut session.stdin, &notification)
            .map_err(|error| error.to_string())?;
        session
            .stdin
            .write_all(b"\n")
            .and_then(|_| session.stdin.flush())
            .map_err(|error| error.to_string())?;
        session.initialized = true;
        Ok(())
    }

    fn rpc(&mut self, name: &str, method: &str, params: Value) -> Result<Value, String> {
        self.ensure_initialized(name)?;
        let config = self
            .configs
            .get(name)
            .cloned()
            .ok_or_else(|| format!("Unknown MCP server: {name}"))?;
        let request = json!({
            "jsonrpc": "2.0",
            "id": self.id(),
            "method": method,
            "params": params
        });
        if config.transport == "http" {
            let session_id = self
                .http_sessions
                .get(name)
                .and_then(|value| value.as_deref());
            Self::http_rpc(&config, &request, session_id).map(|(result, _)| result)
        } else {
            let session = self.sessions.get_mut(name).expect("session initialized");
            Self::stdio_rpc(session, &request)
        }
    }

    pub fn discover(&mut self, name: &str) -> Result<Value, String> {
        self.rpc(name, "tools/list", json!({}))
    }

    pub fn call(&mut self, name: &str, tool: &str, arguments: Value) -> Result<Value, String> {
        if tool.trim().is_empty() {
            return Err("MCP tool name cannot be empty".into());
        }
        self.rpc(
            name,
            "tools/call",
            json!({ "name": tool, "arguments": arguments }),
        )
    }

    pub fn stop_all(&mut self) {
        for session in self.sessions.values_mut() {
            session.stop();
        }
        self.sessions.clear();
        self.http_sessions.clear();
    }
}

impl Drop for McpManager {
    fn drop(&mut self) {
        self.stop_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_stdio_config_with_argv() {
        let config = McpServerConfig {
            name: "filesystem".into(),
            transport: "stdio".into(),
            command: Some("npx".into()),
            args: vec![
                "-y".into(),
                "@modelcontextprotocol/server-filesystem".into(),
            ],
            url: None,
            env: HashMap::new(),
        };
        assert!(config.validate().is_ok());
    }

    #[test]
    fn rejects_insecure_remote_http() {
        let config = McpServerConfig {
            name: "remote".into(),
            transport: "http".into(),
            command: None,
            args: Vec::new(),
            url: Some("http://example.com/mcp".into()),
            env: HashMap::new(),
        };
        assert!(config.validate().is_err());
    }
}
