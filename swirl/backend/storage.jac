"""
Storage utilities for saving and loading workflows.
"""
import json;
import os;
import from pathlib { Path };
import from time { time };

obj WorkflowRecord {
    """A record representing a saved workflow document."""
    has name: str;
    has updated_at: int;
    has workflow: dict;

    def to_dict() -> dict {
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "workflow": self.workflow
        };
    }
}

def safe_name(name: str) -> str {
    """Validates and sanitizes a workflow name."""
    trimmed = name.strip();
    if not trimmed or len(trimmed) > 80 {
        raise ValueError("Workflow name must be 1-80 characters");
    }
    
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_");
    for char in trimmed {
        if char not in allowed {
            raise ValueError("Workflow name may only contain letters, numbers, spaces, - and _");
        }
    }
    
    return trimmed.replace(" ", "_");
}

def data_dir(kind: str) -> str {
    """Returns the storage directory path ~/.swirl/{kind} and creates it if missing."""
    home = str(Path.home());
    path = os.path.join(home, ".swirl", kind);
    os.makedirs(path, exist_ok=True);
    return path;
}

def atomic_json_write(path: str, value: any) {
    """Writes a JSON serializable value to a file atomically."""
    tmp = path + ".tmp";
    with open(tmp, "w") as f {
        json.dump(value, f, indent=2);
    }
    os.rename(tmp, path);
}

def save_workflow(name: str, workflow: dict) -> WorkflowRecord {
    """Validates name, saves workflow to storage, and returns the record."""
    file_name = safe_name(name);
    updated_at = int(time());
    record = WorkflowRecord(name=name.strip(), updated_at=updated_at, workflow=workflow);
    
    dir_path = data_dir("workflows");
    file_path = os.path.join(dir_path, f"{file_name}.json");
    
    atomic_json_write(file_path, record.to_dict());
    return record;
}

def load_workflow(name: str) -> WorkflowRecord {
    """Loads a workflow by name from storage."""
    file_name = safe_name(name);
    dir_path = data_dir("workflows");
    file_path = os.path.join(dir_path, f"{file_name}.json");
    
    with open(file_path, "r") as f {
        data = json.load(f);
    }
    return WorkflowRecord(name=data["name"], updated_at=data["updated_at"], workflow=data["workflow"]);
}

def list_workflows() -> list[WorkflowRecord] {
    """Lists all saved workflows, sorted by updated_at descending."""
    dir_path = data_dir("workflows");
    records = [];
    for file_name in os.listdir(dir_path) {
        if file_name.endswith(".json") {
            file_path = os.path.join(dir_path, file_name);
            with open(file_path, "r") as f {
                data = json.load(f);
                records.append(WorkflowRecord(name=data["name"], updated_at=data["updated_at"], workflow=data["workflow"]));
            }
        }
    }
    records.sort(key=lambda x: x.updated_at, reverse=True);
    return records;
}

def delete_workflow(name: str) -> bool {
    """Deletes a workflow by name if it exists."""
    file_name = safe_name(name);
    dir_path = data_dir("workflows");
    file_path = os.path.join(dir_path, f"{file_name}.json");
    
    if os.path.exists(file_path) {
        os.remove(file_path);
        return True;
    }
    return False;
}

def save_trace(trace: dict) -> str {
    """Saves an execution trace with a timestamp and returns the filename."""
    ts = int(time() * 1000);
    file_name = f"trace-{ts}.json";
    dir_path = data_dir("traces");
    file_path = os.path.join(dir_path, file_name);
    
    atomic_json_write(file_path, trace);
    return file_name;
}

test "safe_name rejects empty names" {
    try {
        safe_name("   ");
        assert False;
    } except ValueError as e {
        assert "1-80 characters" in str(e);
    }
}

test "safe_name rejects special characters" {
    try {
        safe_name("my_workflow_!@#");
        assert False;
    } except ValueError as e {
        assert "only contain letters" in str(e);
    }
}

test "safe_name replaces spaces with underscores" {
    assert safe_name("my workflow name") == "my_workflow_name";
    assert safe_name("  trimmed workflow  ") == "trimmed_workflow";
}

test "safe_name rejects names over 80 chars" {
    long_name = "a" * 81;
    try {
        safe_name(long_name);
        assert False;
    } except ValueError as e {
        assert "1-80 characters" in str(e);
    }
}
