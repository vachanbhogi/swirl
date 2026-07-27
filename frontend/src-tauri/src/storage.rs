use crate::{jac_runtime, models::WorkflowDocument};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::{AppHandle, Manager};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRecord {
    pub name: String,
    pub updated_at: u64,
    pub workflow: WorkflowDocument,
}

fn data_dir(app: &AppHandle) -> Result<String, String> {
    app.path()
        .app_data_dir()
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(|error| format!("Cannot resolve app data directory: {error}"))
}

fn invoke_field<T: DeserializeOwned>(
    app: &AppHandle,
    command: &str,
    payload: Value,
    field: &str,
) -> Result<T, String> {
    let response = jac_runtime::invoke(app, command, &payload)?;
    serde_json::from_value(
        response
            .get(field)
            .cloned()
            .ok_or_else(|| format!("Jac storage response omitted {field}"))?,
    )
    .map_err(|error| format!("Jac storage returned invalid {field}: {error}"))
}

pub fn save_workflow(
    app: &AppHandle,
    name: &str,
    mut workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.migrate_legacy_layout();
    invoke_field(
        app,
        "storage-save",
        json!({
            "dataDir": data_dir(app)?,
            "name": name,
            "workflow": workflow,
        }),
        "record",
    )
}

pub fn create_workflow(
    app: &AppHandle,
    name: &str,
    mut workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.migrate_legacy_layout();
    invoke_field(
        app,
        "storage-create",
        json!({
            "dataDir": data_dir(app)?,
            "name": name,
            "workflow": workflow,
        }),
        "record",
    )
}

pub fn load_workflow(app: &AppHandle, name: &str) -> Result<WorkflowRecord, String> {
    let mut record: WorkflowRecord = invoke_field(
        app,
        "storage-load",
        json!({ "dataDir": data_dir(app)?, "name": name }),
        "record",
    )?;
    record.workflow.migrate_legacy_layout();
    Ok(record)
}

pub fn list_workflows(app: &AppHandle) -> Result<Vec<WorkflowRecord>, String> {
    let mut records: Vec<WorkflowRecord> = invoke_field(
        app,
        "storage-list",
        json!({ "dataDir": data_dir(app)? }),
        "records",
    )?;
    for record in &mut records {
        record.workflow.migrate_legacy_layout();
    }
    Ok(records)
}

pub fn delete_workflow(app: &AppHandle, name: &str) -> Result<bool, String> {
    invoke_field(
        app,
        "storage-delete",
        json!({ "dataDir": data_dir(app)?, "name": name }),
        "deleted",
    )
}

pub fn save_trace(app: &AppHandle, trace: &Value) -> Result<String, String> {
    invoke_field(
        app,
        "storage-trace",
        json!({ "dataDir": data_dir(app)?, "trace": trace }),
        "fileName",
    )
}
