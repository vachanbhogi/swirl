"""Storage helpers for saved workflows and execution traces."""

import json;
import os;
import from time { time }


obj WorkflowRecord {
    has name: str;
    has updated_at: int;
    has workflow: dict;

    def to_dict() -> dict {
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "workflow": self.workflow,
        };
    }
}


def safe_name(name: str) -> str {
    trimmed: str = name.strip();
    if not trimmed or len(trimmed) > 80 {
        raise ValueError("Workflow name must be 1-80 characters");
    }
    allowed: set[str] = set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"
    );
    for char in trimmed {
        if char not in allowed {
            raise ValueError(
                "Workflow name may only contain letters, numbers, spaces, - and _"
            );
        }
    }
    return trimmed.replace(" ", "_");
}


def data_dir(kind: str) -> str {
    path: str = os.path.join(os.path.expanduser("~"), ".swirl", kind);
    os.makedirs(path, exist_ok=True);
    return path;
}


def atomic_json_write(path: str, value: any) {
    temporary: str = path + ".tmp";
    with open(temporary, "w", encoding="utf-8") as handle {
        json.dump(value, handle, indent=2);
    }
    os.replace(temporary, path);
}


def save_workflow(name: str, workflow: dict) -> WorkflowRecord {
    file_name: str = safe_name(name);
    updated_at: int = int(time());
    record: WorkflowRecord = WorkflowRecord(
        name=name.strip(),
        updated_at=updated_at,
        workflow=workflow,
    );
    file_path: str = os.path.join(
        data_dir("workflows"),
        f"{file_name}.json",
    );
    atomic_json_write(file_path, record.to_dict());
    return record;
}


def load_workflow(name: str) -> WorkflowRecord {
    file_name: str = safe_name(name);
    file_path: str = os.path.join(
        data_dir("workflows"),
        f"{file_name}.json",
    );
    with open(file_path, "r", encoding="utf-8") as handle {
        data: dict = json.load(handle) as dict;
    }
    return WorkflowRecord(
        name=str(data["name"]),
        updated_at=int(data["updated_at"]),
        workflow=data["workflow"] as dict,
    );
}


def list_workflows() -> list[WorkflowRecord] {
    directory: str = data_dir("workflows");
    records: list[WorkflowRecord] = [];
    for file_name in os.listdir(directory) {
        if file_name.endswith(".json") {
            file_path: str = os.path.join(directory, file_name);
            with open(file_path, "r", encoding="utf-8") as handle {
                data: dict = json.load(handle) as dict;
            }
            records.append(
                WorkflowRecord(
                    name=str(data["name"]),
                    updated_at=int(data["updated_at"]),
                    workflow=data["workflow"] as dict,
                )
            );
        }
    }
    records.sort(
        key=lambda (record: WorkflowRecord) { record.updated_at; },
        reverse=True,
    );
    return records;
}


def delete_workflow(name: str) -> bool {
    file_name: str = safe_name(name);
    file_path: str = os.path.join(
        data_dir("workflows"),
        f"{file_name}.json",
    );
    if os.path.exists(file_path) {
        os.remove(file_path);
        return True;
    }
    return False;
}


def save_trace(trace: dict) -> str {
    timestamp: int = int(time() * 1000);
    file_name: str = f"trace-{timestamp}.json";
    file_path: str = os.path.join(data_dir("traces"), file_name);
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
