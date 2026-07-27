"""Jac-owned workflow and execution-trace persistence."""

import json;
import os;
import from time { time }
import from backend.models { validate_workflow }

glob MAX_WORKFLOW_NAME_LENGTH: int = 80;


obj WorkflowRecord {
    has name: str;
    has updated_at: int;
    has workflow: dict;

    def to_dict() -> dict {
        return {
            "name": self.name,
            "updatedAt": self.updated_at,
            "workflow": self.workflow,
        };
    }
}


def safe_name(name: str) -> str {
    trimmed: str = name.strip();
    if not trimmed or len(trimmed) > MAX_WORKFLOW_NAME_LENGTH {
        raise ValueError("Workflow name must be 1-80 characters");
    }
    allowed: set[str] = set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"
    );
    for character in trimmed {
        if character not in allowed {
            raise ValueError(
                "Workflow name may only contain letters, numbers, spaces, - and _"
            );
        }
    }
    return trimmed.replace(" ", "_");
}


def storage_root(base_dir: str = "") -> str {
    return (
        os.path.abspath(base_dir)
        if base_dir.strip()
        else os.path.join(os.path.expanduser("~"), ".swirl")
    );
}


def data_dir(kind: str, base_dir: str = "") -> str {
    path: str = os.path.join(storage_root(base_dir), kind);
    os.makedirs(path, exist_ok=True);
    return path;
}


def atomic_json_write(path: str, value: any) {
    temporary: str = path + ".tmp";
    try {
        with open(temporary, "w", encoding="utf-8") as handle {
            json.dump(value, handle, indent=2);
            handle.flush();
            os.fsync(handle.fileno());
        }
        os.replace(temporary, path);
    } finally {
        if os.path.exists(temporary) {
            os.remove(temporary);
        }
    }
}


def create_json_file(path: str, value: any) -> bool {
    try {
        with open(path, "x", encoding="utf-8") as handle {
            json.dump(value, handle, indent=2);
            handle.flush();
            os.fsync(handle.fileno());
        }
        return True;
    } except FileExistsError {
        return False;
    } except Exception {
        if os.path.exists(path) {
            os.remove(path);
        }
        raise;
    }
}


def numbered_name(base: str, number: int) -> str {
    suffix: str = "" if number == 1 else f" {number}";
    stem_length: int = MAX_WORKFLOW_NAME_LENGTH - len(suffix);
    return (base[:stem_length].rstrip() + suffix);
}


def workflow_record(name: str, workflow: dict) -> WorkflowRecord {
    return WorkflowRecord(
        name=name.strip(),
        updated_at=int(time()),
        workflow=workflow,
    );
}


def record_from_data(data: dict) -> WorkflowRecord {
    updated_at: int = int(
        data.get("updatedAt", data.get("updated_at", 0))
    );
    return WorkflowRecord(
        name=str(data.get("name", "")),
        updated_at=updated_at,
        workflow=data.get("workflow", {}) as dict,
    );
}


def ensure_record_name(record: WorkflowRecord, requested_name: str) {
    if record.name != requested_name.strip() {
        raise ValueError(
            "Workflow name conflicts with existing workflow \""
            + record.name
            + "\" after filename normalization"
        );
    }
}


def record_path(name: str, base_dir: str = "") -> str {
    return os.path.join(
        data_dir("workflows", base_dir),
        safe_name(name) + ".json",
    );
}


def save_workflow(
    name: str,
    workflow: dict,
    base_dir: str = "",
) -> WorkflowRecord {
    validate_workflow(workflow);
    file_path: str = record_path(name, base_dir);
    if os.path.exists(file_path) {
        with open(file_path, "r", encoding="utf-8") as handle {
            existing = record_from_data(json.load(handle) as dict);
        }
        ensure_record_name(existing, name);
    }
    record: WorkflowRecord = workflow_record(name, workflow);
    atomic_json_write(file_path, record.to_dict());
    return record;
}


def create_workflow(
    name: str,
    workflow: dict,
    base_dir: str = "",
) -> WorkflowRecord {
    validate_workflow(workflow);
    base_name: str = name.strip();
    safe_name(base_name);
    directory: str = data_dir("workflows", base_dir);
    for number in range(1, 10001) {
        candidate: str = numbered_name(base_name, number);
        file_path: str = os.path.join(
            directory,
            safe_name(candidate) + ".json",
        );
        record: WorkflowRecord = workflow_record(candidate, workflow);
        if create_json_file(file_path, record.to_dict()) {
            return record;
        }
    }
    raise RuntimeError("Could not allocate a unique workflow project name");
}


def load_workflow(name: str, base_dir: str = "") -> WorkflowRecord {
    with open(record_path(name, base_dir), "r", encoding="utf-8") as handle {
        record = record_from_data(json.load(handle) as dict);
    }
    ensure_record_name(record, name);
    return record;
}


def list_workflows(base_dir: str = "") -> list[WorkflowRecord] {
    directory: str = data_dir("workflows", base_dir);
    records: list[WorkflowRecord] = [];
    for file_name in os.listdir(directory) {
        if not file_name.endswith(".json") {
            continue;
        }
        file_path: str = os.path.join(directory, file_name);
        with open(file_path, "r", encoding="utf-8") as handle {
            records.append(record_from_data(json.load(handle) as dict));
        }
    }
    records.sort(
        key=lambda (record: WorkflowRecord) { record.updated_at; },
        reverse=True,
    );
    return records;
}


def delete_workflow(name: str, base_dir: str = "") -> bool {
    file_path: str = record_path(name, base_dir);
    if not os.path.exists(file_path) {
        return False;
    }
    with open(file_path, "r", encoding="utf-8") as handle {
        record = record_from_data(json.load(handle) as dict);
    }
    ensure_record_name(record, name);
    os.remove(file_path);
    return True;
}


def save_trace(trace: dict, base_dir: str = "") -> str {
    timestamp: int = int(time() * 1000);
    file_name: str = f"trace-{timestamp}.json";
    file_path: str = os.path.join(data_dir("traces", base_dir), file_name);
    atomic_json_write(file_path, trace);
    return file_name;
}


test "safe_name rejects empty names" {
    try {
        safe_name("   ");
        assert False;
    } except ValueError as error {
        assert "1-80 characters" in str(error);
    }
}


test "safe_name rejects special characters" {
    try {
        safe_name("my_workflow_!@#");
        assert False;
    } except ValueError as error {
        assert "only contain letters" in str(error);
    }
}


test "safe_name replaces spaces with underscores" {
    assert safe_name("my workflow name") == "my_workflow_name";
    assert safe_name("  trimmed workflow  ") == "trimmed_workflow";
}


test "safe_name rejects names over 80 chars" {
    try {
        safe_name("a" * 81);
        assert False;
    } except ValueError as error {
        assert "1-80 characters" in str(error);
    }
}


test "numbered names stay within the storage limit" {
    base: str = "A" * 80;
    assert numbered_name(base, 1) == base;
    assert numbered_name(base, 2) == ("A" * 78) + " 2";
    assert numbered_name("Daily Brief", 3) == "Daily Brief 3";
}
