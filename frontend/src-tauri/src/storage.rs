use crate::models::WorkflowDocument;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs::{self, OpenOptions},
    io::{ErrorKind, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};

const MAX_WORKFLOW_NAME_LENGTH: usize = 80;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRecord {
    pub name: String,
    pub updated_at: u64,
    pub workflow: WorkflowDocument,
}

fn safe_name(name: &str) -> Result<String, String> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.len() > MAX_WORKFLOW_NAME_LENGTH {
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

fn ensure_record_name(record: &WorkflowRecord, requested_name: &str) -> Result<(), String> {
    if record.name == requested_name.trim() {
        Ok(())
    } else {
        Err(format!(
            "Workflow name conflicts with existing workflow \"{}\" after filename normalization",
            record.name
        ))
    }
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

fn create_json_file(path: &Path, value: &impl Serialize) -> Result<bool, String> {
    let bytes = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
    let mut file = match OpenOptions::new().write(true).create_new(true).open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::AlreadyExists => return Ok(false),
        Err(error) => return Err(error.to_string()),
    };
    if let Err(error) = file.write_all(&bytes).and_then(|_| file.sync_all()) {
        let _ = fs::remove_file(path);
        return Err(error.to_string());
    }
    Ok(true)
}

fn numbered_name(base: &str, number: usize) -> String {
    let suffix = if number == 1 {
        String::new()
    } else {
        format!(" {number}")
    };
    let stem_length = MAX_WORKFLOW_NAME_LENGTH.saturating_sub(suffix.len());
    let stem = base.chars().take(stem_length).collect::<String>();
    format!("{}{}", stem.trim_end(), suffix)
}

fn workflow_record(name: &str, workflow: WorkflowDocument) -> Result<WorkflowRecord, String> {
    let updated_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_secs();
    Ok(WorkflowRecord {
        name: name.trim().to_string(),
        updated_at,
        workflow,
    })
}

pub fn save_workflow(
    app: &AppHandle,
    name: &str,
    mut workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.migrate_legacy_layout();
    workflow.validate()?;
    let file_name = safe_name(name)?;
    let path = data_dir(app, "workflows")?.join(format!("{file_name}.json"));
    if path.exists() {
        let existing: WorkflowRecord =
            serde_json::from_slice(&fs::read(&path).map_err(|error| error.to_string())?)
                .map_err(|error| error.to_string())?;
        ensure_record_name(&existing, name)?;
    }
    let record = workflow_record(name, workflow)?;
    atomic_json_write(&path, &record)?;
    Ok(record)
}

pub fn create_workflow(
    app: &AppHandle,
    name: &str,
    mut workflow: WorkflowDocument,
) -> Result<WorkflowRecord, String> {
    workflow.migrate_legacy_layout();
    workflow.validate()?;
    let base_name = name.trim();
    safe_name(base_name)?;
    let directory = data_dir(app, "workflows")?;

    for number in 1..=10_000 {
        let candidate = numbered_name(base_name, number);
        let file_name = safe_name(&candidate)?;
        let path = directory.join(format!("{file_name}.json"));
        let record = workflow_record(&candidate, workflow.clone())?;
        if create_json_file(&path, &record)? {
            return Ok(record);
        }
    }
    Err("Could not allocate a unique workflow project name".into())
}

pub fn load_workflow(app: &AppHandle, name: &str) -> Result<WorkflowRecord, String> {
    let file_name = safe_name(name)?;
    let bytes = fs::read(data_dir(app, "workflows")?.join(format!("{file_name}.json")))
        .map_err(|error| error.to_string())?;
    let mut record: WorkflowRecord =
        serde_json::from_slice(&bytes).map_err(|error| error.to_string())?;
    ensure_record_name(&record, name)?;
    record.workflow.migrate_legacy_layout();
    Ok(record)
}

pub fn list_workflows(app: &AppHandle) -> Result<Vec<WorkflowRecord>, String> {
    let mut records = Vec::new();
    for entry in fs::read_dir(data_dir(app, "workflows")?).map_err(|error| error.to_string())? {
        let path = entry.map_err(|error| error.to_string())?.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let bytes = fs::read(path).map_err(|error| error.to_string())?;
        let mut record: WorkflowRecord =
            serde_json::from_slice(&bytes).map_err(|error| error.to_string())?;
        record.workflow.migrate_legacy_layout();
        records.push(record);
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
    let record: WorkflowRecord =
        serde_json::from_slice(&fs::read(&path).map_err(|error| error.to_string())?)
            .map_err(|error| error.to_string())?;
    ensure_record_name(&record, name)?;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_names_that_share_a_normalized_filename() {
        let record = WorkflowRecord {
            name: "Daily Brief".into(),
            updated_at: 0,
            workflow: WorkflowDocument {
                nodes: Vec::new(),
                edges: Vec::new(),
            },
        };
        assert!(ensure_record_name(&record, "Daily_Brief").is_err());
        assert!(ensure_record_name(&record, "Daily Brief").is_ok());
    }

    #[test]
    fn generated_names_add_a_suffix_without_exceeding_the_limit() {
        let base = "A".repeat(80);
        assert_eq!(numbered_name(&base, 1), base);
        assert_eq!(numbered_name(&base, 2), format!("{} 2", "A".repeat(78)));
        assert_eq!(numbered_name("Daily Brief", 3), "Daily Brief 3");
    }

    #[test]
    fn create_only_write_preserves_an_existing_project() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!("swirl-storage-test-{unique}"));
        fs::create_dir(&directory).unwrap();
        let path = directory.join("project.json");

        assert!(create_json_file(&path, &serde_json::json!({ "version": 1 })).unwrap());
        assert!(!create_json_file(&path, &serde_json::json!({ "version": 2 })).unwrap());
        let stored: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(stored["version"], 1);

        fs::remove_dir_all(directory).unwrap();
    }
}
