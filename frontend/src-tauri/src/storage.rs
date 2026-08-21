use crate::{
    jac_runtime,
    models::{GeneratedAppToolRecord, GeneratedAppToolVersion, WorkflowDocument},
};
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

fn log_positions(operation: &str, name: &str, workflow: &WorkflowDocument) {
    let positions = workflow
        .nodes
        .iter()
        .map(|node| {
            format!(
                "{}=({:.1}, {:.1})",
                node.id, node.position.x, node.position.y
            )
        })
        .collect::<Vec<_>>()
        .join(", ");
    println!(
        "[Swirl][Storage] {operation} '{name}' — {} node(s); positions: [{positions}]",
        workflow.nodes.len()
    );
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
    log_positions("saving", name, &workflow);
    let record = invoke_field(
        app,
        "storage-save",
        json!({
            "dataDir": data_dir(app)?,
            "name": name,
            "workflow": workflow,
        }),
        "record",
    )?;
    println!("[Swirl][Storage] saved '{name}' successfully");
    Ok(record)
}

pub fn create_workflow(
    app: &AppHandle,
    name: &str,
    mut workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.migrate_legacy_layout();
    log_positions("creating", name, &workflow);
    let record: WorkflowRecord = invoke_field(
        app,
        "storage-create",
        json!({
            "dataDir": data_dir(app)?,
            "name": name,
            "workflow": workflow,
        }),
        "record",
    )?;
    println!("[Swirl][Storage] created workflow '{}'", record.name);
    Ok(record)
}

pub fn load_workflow(app: &AppHandle, name: &str) -> Result<WorkflowRecord, String> {
    let mut record: WorkflowRecord = invoke_field(
        app,
        "storage-load",
        json!({ "dataDir": data_dir(app)?, "name": name }),
        "record",
    )?;
    record.workflow.migrate_legacy_layout();
    log_positions("loaded", &record.name, &record.workflow);
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
    println!(
        "[Swirl][Storage] listed {} saved workflow(s)",
        records.len()
    );
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

pub fn create_app_tool(
    app: &AppHandle,
    version: &GeneratedAppToolVersion,
) -> Result<GeneratedAppToolRecord, String> {
    println!(
        "[Swirl][GeneratedTools] creating id={} version={} app='{}' validation={} (runtime values redacted)",
        version.id,
        version.version,
        version.target.application_name,
        version.validation.status
    );
    invoke_field(
        app,
        "tool-create",
        json!({ "dataDir": data_dir(app)?, "tool": version }),
        "record",
    )
}

pub fn list_app_tools(app: &AppHandle) -> Result<Vec<GeneratedAppToolRecord>, String> {
    let records = invoke_field(
        app,
        "tool-list",
        json!({ "dataDir": data_dir(app)? }),
        "records",
    )?;
    println!("[Swirl][GeneratedTools] listed generated application tools");
    Ok(records)
}

pub fn load_app_tool(
    app: &AppHandle,
    id: &str,
    version: Option<u64>,
) -> Result<GeneratedAppToolVersion, String> {
    let loaded = invoke_field(
        app,
        "tool-load",
        json!({ "dataDir": data_dir(app)?, "id": id, "version": version }),
        "version",
    )?;
    println!(
        "[Swirl][GeneratedTools] loaded id={id} version={} (runtime values redacted)",
        version
            .map(|value| value.to_string())
            .unwrap_or_else(|| "latest".into())
    );
    Ok(loaded)
}

pub fn publish_app_tool_version(
    app: &AppHandle,
    id: &str,
    version: &GeneratedAppToolVersion,
) -> Result<GeneratedAppToolRecord, String> {
    println!(
        "[Swirl][GeneratedTools] publishing id={id} version={} app='{}' validation={} (runtime values redacted)",
        version.version,
        version.target.application_name,
        version.validation.status
    );
    invoke_field(
        app,
        "tool-publish",
        json!({ "dataDir": data_dir(app)?, "id": id, "tool": version }),
        "record",
    )
}

pub fn archive_app_tool(app: &AppHandle, id: &str) -> Result<bool, String> {
    let archived = invoke_field(
        app,
        "tool-archive",
        json!({ "dataDir": data_dir(app)?, "id": id }),
        "archived",
    )?;
    println!("[Swirl][GeneratedTools] archived id={id}; pinned workflow snapshots remain intact");
    Ok(archived)
}
