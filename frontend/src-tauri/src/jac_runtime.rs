use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};

const SENTINEL: &str = "__SWIRL_JSON__";
static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

fn runtime_script(app: &AppHandle) -> Result<PathBuf, String> {
    let mut candidates = Vec::new();
    if let Ok(resource_dir) = app.path().resource_dir() {
        candidates.push(resource_dir.join("backend/swirl_runtime.jac"));
        candidates.push(resource_dir.join("swirl_runtime.jac"));
        candidates.push(resource_dir.join("_up_/_up_/backend/swirl_runtime.jac"));
    }
    candidates.push(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join("backend/swirl_runtime.jac"),
    );
    candidates
        .into_iter()
        .find(|path| path.is_file())
        .ok_or_else(|| "Bundled Jac runtime was not found".to_string())
}

fn jac_binary(app: &AppHandle) -> PathBuf {
    let mut candidates = Vec::new();
    if let Some(explicit) = std::env::var_os("SWIRL_JAC_BIN") {
        candidates.push(PathBuf::from(explicit));
    }
    if let Ok(resource_dir) = app.path().resource_dir() {
        candidates.push(resource_dir.join("bin/jac"));
        candidates.push(resource_dir.join("jac"));
    }
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        candidates.push(home.join(".local/bin/jac"));
        candidates.push(home.join(".jac/bin/jac"));
    }
    candidates.push(PathBuf::from("/opt/homebrew/bin/jac"));
    candidates.push(PathBuf::from("/usr/local/bin/jac"));
    candidates
        .into_iter()
        .find(|path| path.is_file())
        .unwrap_or_else(|| PathBuf::from("jac"))
}

fn unique_payload_path(app: &AppHandle) -> Result<PathBuf, String> {
    let cache_dir = app
        .path()
        .app_cache_dir()
        .map_err(|error| format!("Cannot resolve app cache directory: {error}"))?
        .join("runtime");
    fs::create_dir_all(&cache_dir)
        .map_err(|error| format!("Cannot create Jac runtime cache: {error}"))?;
    let epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let counter = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    Ok(cache_dir.join(format!("payload-{epoch}-{counter}.json")))
}

fn project_root(script: &Path) -> &Path {
    script
        .parent()
        .and_then(Path::parent)
        .unwrap_or_else(|| script.parent().unwrap_or(Path::new(".")))
}

pub fn invoke(app: &AppHandle, command: &str, payload: &Value) -> Result<Value, String> {
    let script = runtime_script(app)?;
    let payload_path = unique_payload_path(app)?;
    let encoded = serde_json::to_vec(payload)
        .map_err(|error| format!("Cannot serialize Jac runtime payload: {error}"))?;
    fs::write(&payload_path, encoded)
        .map_err(|error| format!("Cannot write Jac runtime payload: {error}"))?;

    let output = Command::new(jac_binary(app))
        .arg("run")
        .arg("--no-cache")
        .arg(&script)
        .arg(command)
        .arg(&payload_path)
        .current_dir(project_root(&script))
        .output();
    let _ = fs::remove_file(&payload_path);
    let output = output.map_err(|error| format!("Cannot launch Jac runtime: {error}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let envelope = stdout
        .lines()
        .rev()
        .find_map(|line| line.strip_prefix(SENTINEL))
        .ok_or_else(|| {
            let stderr = String::from_utf8_lossy(&output.stderr);
            format!(
                "Jac runtime returned no structured response{}",
                if stderr.trim().is_empty() {
                    String::new()
                } else {
                    format!(": {}", stderr.trim())
                }
            )
        })?;
    let parsed: Value = serde_json::from_str(envelope)
        .map_err(|error| format!("Invalid Jac runtime response: {error}"))?;
    if parsed.get("ok").and_then(Value::as_bool) != Some(true) {
        return Err(parsed
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("Jac runtime command failed")
            .to_string());
    }
    parsed
        .get("data")
        .cloned()
        .ok_or_else(|| "Jac runtime response omitted data".to_string())
}

pub fn health(app: &AppHandle) -> Value {
    let script = runtime_script(app);
    let version = Command::new(jac_binary(app))
        .arg("--version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string());
    serde_json::json!({
        "status": if script.is_ok() && version.is_some() { "online" } else { "degraded" },
        "system": "Swirl Jac Graph-Walker Runtime",
        "jacVersion": version,
        "runtimeFound": script.is_ok(),
        "transport": "tauri-ipc"
    })
}
