use crate::models::WorkflowDocument;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRecord {
    pub name: String,
    pub updated_at: u64,
    pub workflow: WorkflowDocument,
}

fn safe_name(name: &str) -> Result<String, String> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.len() > 80 {
        return Err("Workflow name must be 1-80 characters".into());
    }
    if !trimmed
        .chars()
        .all(|character| character.is_ascii_alphanumeric() || matches!(character, ' ' | '-' | '_'))
    {
        return Err("Workflow name may only contain letters, numbers, spaces, - and _".into());
    }
    Ok(trimmed.replace(' ', "_"))
}

fn data_dir(app: &AppHandle, kind: &str) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|error| error.to_string())?
        .join(kind);
    fs::create_dir_all(&dir).map_err(|error| error.to_string())?;
    Ok(dir)
}

fn atomic_json_write(path: &Path, value: &impl Serialize) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
    let temporary = path.with_extension("tmp");
    fs::write(&temporary, bytes).map_err(|error| error.to_string())?;
    fs::rename(&temporary, path).map_err(|error| error.to_string())
}

pub fn save_workflow(
    app: &AppHandle,
    name: &str,
    workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.validate()?;
    let file_name = safe_name(name)?;
    let updated_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_secs();
    let record = WorkflowRecord {
        name: name.trim().to_string(),
        updated_at,
        workflow,
    };
    atomic_json_write(
        &data_dir(app, "workflows")?.join(format!("{file_name}.json")),
        &record,
    )?;
    Ok(record)
}

pub fn load_workflow(app: &AppHandle, name: &str) -> Result<WorkflowRecord, String> {
    let file_name = safe_name(name)?;
    let bytes = fs::read(data_dir(app, "workflows")?.join(format!("{file_name}.json")))
        .map_err(|error| error.to_string())?;
    serde_json::from_slice(&bytes).map_err(|error| error.to_string())
}

pub fn list_workflows(app: &AppHandle) -> Result<Vec<WorkflowRecord>, String> {
    let mut records = Vec::new();
    for entry in fs::read_dir(data_dir(app, "workflows")?).map_err(|error| error.to_string())? {
        let path = entry.map_err(|error| error.to_string())?.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let bytes = fs::read(path).map_err(|error| error.to_string())?;
        records.push(serde_json::from_slice(&bytes).map_err(|error| error.to_string())?);
    }
    records.sort_by(|left: &WorkflowRecord, right: &WorkflowRecord| {
        right.updated_at.cmp(&left.updated_at)
    });
    Ok(records)
}

pub fn delete_workflow(app: &AppHandle, name: &str) -> Result<bool, String> {
    let file_name = safe_name(name)?;
    let path = data_dir(app, "workflows")?.join(format!("{file_name}.json"));
    if !path.exists() {
        return Ok(false);
    }
    fs::remove_file(path).map_err(|error| error.to_string())?;
    Ok(true)
}

pub fn save_trace(app: &AppHandle, trace: &Value) -> Result<String, String> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_millis();
    let file_name = format!("trace-{timestamp}.json");
    atomic_json_write(&data_dir(app, "traces")?.join(&file_name), trace)?;
    Ok(file_name)
}
