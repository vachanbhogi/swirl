"""Jac-owned workflow and execution-trace persistence."""

import json;
import os;
import tempfile;
import from time { time }
import from backend.models { validate_workflow }

glob MAX_WORKFLOW_NAME_LENGTH: int = 80;
glob APP_TOOL_SCHEMA_VERSION: int = 1;


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


obj AppToolRecord {
    has tool_id: str;
    has name: str;
    has description: str;
    has archived: bool = False;
    has latest_version: int = 1;
    has created_at: int = 0;
    has updated_at: int = 0;
    has archived_at: int = 0;
    has versions: list[dict] = [];

    def to_dict() -> dict {
        return {
            "schemaVersion": APP_TOOL_SCHEMA_VERSION,
            "id": self.tool_id,
            "name": self.name,
            "description": self.description,
            "archived": self.archived,
            "latestVersion": self.latest_version,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
            "archivedAt": self.archived_at,
            "versions": self.versions,
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


def workflow_with_positions(workflow: dict) -> dict {
    positioned_nodes: list[dict] = [];
    for raw_node in (workflow.get("nodes", []) as list) {
        node_spec: dict = raw_node as dict;
        current: dict = (
            node_spec.get("position") as dict
            if isinstance(node_spec.get("position"), dict)
            else {}
        );
        x_value: any = current.get("x", node_spec.get("x", 250.0));
        y_value: any = current.get("y", node_spec.get("y", 180.0));
        positioned_nodes.append({
            **node_spec,
            "position": {
                "x": float(x_value),
                "y": float(y_value),
            },
        });
    }
    return {**workflow, "nodes": positioned_nodes};
}


def _stored_node(raw_node: dict) -> dict {
    stored: dict = {};
    forbidden_top_level: set[str] = {
        "preparedScript", "runtimeScript", "approvalToken", "runtimeValues"
    };
    for key in raw_node {
        if key not in forbidden_top_level {
            stored[key] = raw_node[key];
        }
    }
    config_value: any = raw_node.get("config", {});
    if not isinstance(config_value, dict) {
        stored["config"] = {};
        return stored;
    }
    config: dict = config_value as dict;
    clean_config: dict = {};
    forbidden_config: set[str] = {
        "preparedScript", "preparedExplanation", "runtimeScript",
        "approvalToken", "approvalTokens", "runtimeValues",
        "resolvedArguments"
    };
    for key in config {
        if key not in forbidden_config {
            clean_config[key] = config[key];
        }
    }
    if str(raw_node.get("type", "")) == "generated_app_tool" {
        snapshot_value: any = raw_node.get("toolSnapshot", {});
        bindings_value: any = clean_config.get("bindings", {});
        if isinstance(snapshot_value, dict) and isinstance(bindings_value, dict) {
            sensitive: set[str] = set();
            inputs_value: any = (snapshot_value as dict).get("inputs", []);
            if isinstance(inputs_value, list) {
                for input_value in (inputs_value as list) {
                    if (
                        isinstance(input_value, dict)
                        and bool((input_value as dict).get("sensitive", False))
                    ) {
                        sensitive.add(str((input_value as dict).get("key", "")));
                    }
                }
            }
            stored_bindings: dict = {};
            for binding_key in (bindings_value as dict) {
                binding_value: any = (bindings_value as dict)[binding_key];
                if isinstance(binding_value, dict) {
                    binding: dict = binding_value as dict;
                    if (
                        binding_key in sensitive
                        and str(binding.get("kind", "")) == "literal"
                    ) {
                        stored_bindings[binding_key] = {
                            **binding, "value": ""
                        };
                    } else {
                        stored_bindings[binding_key] = binding;
                    }
                }
            }
            clean_config["bindings"] = stored_bindings;
        }
    }
    stored["config"] = clean_config;
    return stored;
}


def workflow_for_storage(workflow: dict) -> dict {
    positioned: dict = workflow_with_positions(workflow);
    stored_nodes: list[dict] = [];
    for raw_node in (positioned.get("nodes", []) as list) {
        stored_nodes.append(_stored_node(raw_node as dict));
    }
    return {**positioned, "nodes": stored_nodes};
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
        workflow=workflow_with_positions(
            data.get("workflow", {}) as dict
        ),
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
    positioned: dict = workflow_for_storage(workflow);
    validate_workflow(positioned);
    file_path: str = record_path(name, base_dir);
    if os.path.exists(file_path) {
        with open(file_path, "r", encoding="utf-8") as handle {
            existing = record_from_data(json.load(handle) as dict);
        }
        ensure_record_name(existing, name);
    }
    record: WorkflowRecord = workflow_record(name, positioned);
    atomic_json_write(file_path, record.to_dict());
    return record;
}


def create_workflow(
    name: str,
    workflow: dict,
    base_dir: str = "",
) -> WorkflowRecord {
    positioned: dict = workflow_for_storage(workflow);
    validate_workflow(positioned);
    base_name: str = name.strip();
    safe_name(base_name);
    directory: str = data_dir("workflows", base_dir);
    for number in range(1, 10001) {
        candidate: str = numbered_name(base_name, number);
        file_path: str = os.path.join(
            directory,
            safe_name(candidate) + ".json",
        );
        record: WorkflowRecord = workflow_record(candidate, positioned);
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


def safe_tool_id(tool_id: str) -> str {
    trimmed: str = tool_id.strip().lower();
    if not trimmed or len(trimmed) > 120 {
        raise ValueError("Tool ID must be 1-120 characters");
    }
    allowed: set[str] = set(
        "abcdefghijklmnopqrstuvwxyz0123456789-_"
    );
    for character in trimmed {
        if character not in allowed {
            raise ValueError(
                "Tool ID may only contain lowercase letters, numbers, - and _"
            );
        }
    }
    return trimmed;
}


def _sha256_fingerprint(value: str) -> str {
    fingerprint: str = value.strip().lower();
    if len(fingerprint) != 64 {
        raise ValueError("Tool fingerprint must be a 64-character SHA-256 digest");
    }
    allowed: set[str] = set("0123456789abcdef");
    for character in fingerprint {
        if character not in allowed {
            raise ValueError("Tool fingerprint must be lowercase hexadecimal SHA-256");
        }
    }
    return fingerprint;
}


def _tool_version_for_storage(
    raw: dict,
    expected_id: str = "",
    expected_version: int = 0,
) -> dict {
    tool_id: str = safe_tool_id(
        expected_id if expected_id.strip() else str(raw.get("id", ""))
    );
    version: int = int(raw.get("version", expected_version));
    if expected_version and version != expected_version {
        raise ValueError(
            f"Tool version must be the next immutable version ({expected_version})"
        );
    }
    if version < 1 {
        raise ValueError("Tool version must be a positive integer");
    }
    name: str = str(raw.get("name", "")).strip();
    description: str = str(raw.get("description", "")).strip();
    if not name or len(name) > 80 {
        raise ValueError("Tool name must be 1-80 characters");
    }
    if not description or len(description) > 300 {
        raise ValueError("Tool description must be 1-300 characters");
    }
    target_value: any = raw.get("target");
    inputs_value: any = raw.get("inputs");
    program_value: any = raw.get("program");
    effects_value: any = raw.get("effects");
    if not isinstance(target_value, dict) {
        raise ValueError("Tool version target must be an object");
    }
    if not isinstance(inputs_value, list) or not isinstance(program_value, list) {
        raise ValueError("Tool version inputs and program must be lists");
    }
    if not isinstance(effects_value, list) {
        raise ValueError("Tool version effects must be a list");
    }
    target: dict = target_value as dict;
    application_name: str = str(target.get("applicationName", "")).strip();
    bundle_id: str = str(target.get("bundleId", "")).strip();
    process_name: str = str(target.get("processName", "")).strip();
    automation_mode: str = str(
        target.get("automationMode", "accessibility")
    );
    if not application_name or not bundle_id or not process_name {
        raise ValueError(
            "Resolved target requires applicationName, bundleId, and processName"
        );
    }
    if automation_mode not in {"accessibility", "apple_events", "hybrid"} {
        raise ValueError(f"Unsupported automation mode: {automation_mode}");
    }
    inputs: list = inputs_value as list;
    input_keys: set[str] = set();
    stored_inputs: list[dict] = [];
    for input_value in inputs {
        if not isinstance(input_value, dict) {
            raise ValueError("Every tool input must be an object");
        }
        input_spec: dict = input_value as dict;
        key: str = str(input_spec.get("key", "")).strip();
        if not key or key in input_keys {
            raise ValueError("Tool input keys must be unique and non-empty");
        }
        input_keys.add(key);
        input_type: str = str(input_spec.get("inputType", "string"));
        if input_type not in {"string", "text", "multiline", "number", "boolean"} {
            raise ValueError(f"Unsupported tool input type: {input_type}");
        }
        stored_inputs.append({
            "key": key,
            "label": str(input_spec.get("label", key)).strip(),
            "inputType": input_type,
            "required": bool(input_spec.get("required", True)),
            "defaultValue": str(input_spec.get("defaultValue", "")),
            "sensitive": bool(input_spec.get("sensitive", True)),
            "description": str(input_spec.get("description", "")),
        });
    }
    allowed_ops: set[str] = {
        "activate_app", "wait_frontmost", "wait", "key_chord",
        "press_key", "type_input", "wait_element", "click_element",
        "read_element"
    };
    if not program_value or len(program_value as list) > 64 {
        raise ValueError("Validated tool program must contain 1-64 operations");
    }
    stored_program: list[dict] = [];
    index: int = 0;
    for step_value in (program_value as list) {
        index += 1;
        if not isinstance(step_value, dict) {
            raise ValueError(f"Tool program step {index} must be an object");
        }
        step: dict = step_value as dict;
        op: str = str(step.get("op", ""));
        if op not in allowed_ops {
            raise ValueError(f"Unsupported tool operation at step {index}: {op}");
        }
        forbidden_step_keys: set[str] = {
            "script", "command", "shell", "application", "bundleId",
            "x", "y", "coordinates", "url", "code"
        };
        for key in step {
            if key in forbidden_step_keys {
                raise ValueError(
                    f"Forbidden field in tool operation {index}: {key}"
                );
            }
        }
        if op == "type_input" {
            input_key: str = str(step.get("inputKey", ""));
            if input_key not in input_keys {
                raise ValueError(
                    f"Tool operation {index} references unknown input: {input_key}"
                );
            }
        }
        if op == "wait" {
            seconds: float = float(step.get("seconds", 0.0));
            if seconds <= 0.0 or seconds > 10.0 {
                raise ValueError("Tool waits must be greater than 0 and at most 10 seconds");
            }
        }
        if op in {"wait_element", "click_element", "read_element"} {
            selector_value: any = step.get("selector");
            if not isinstance(selector_value, dict) {
                raise ValueError(f"Tool operation {index} requires a selector");
            }
            selector: dict = selector_value as dict;
            if not (
                str(selector.get("role", "")).strip()
                or str(selector.get("title", "")).strip()
                or str(selector.get("identifier", "")).strip()
            ) {
                raise ValueError(f"Tool operation {index} selector cannot be empty");
            }
            timeout: float = float(step.get("timeoutSec", 5.0));
            if timeout <= 0.0 or timeout > 15.0 {
                raise ValueError("Accessibility selector timeout must be 0-15 seconds");
            }
        }
        stored_program.append(step);
    }
    if str((stored_program[0] as dict).get("op", "")) != "activate_app" {
        raise ValueError("Validated tool program must begin with activate_app");
    }
    if (
        len(stored_program) < 2
        or str((stored_program[1] as dict).get("op", "")) != "wait_frontmost"
    ) {
        raise ValueError("Validated tool program must verify target focus second");
    }
    stored_effects: list[dict] = [];
    allowed_effects: set[str] = {
        "navigation", "read", "create", "edit", "message", "send"
    };
    approval_effects: set[str] = {"create", "edit", "message", "send"};
    for effect_value in (effects_value as list) {
        if not isinstance(effect_value, dict) {
            raise ValueError("Every tool effect must be an object");
        }
        effect: dict = effect_value as dict;
        effect_type: str = str(effect.get("type", ""));
        requires_approval: bool = bool(effect.get("requiresApproval", False));
        if effect_type not in allowed_effects {
            raise ValueError(f"Unsupported external effect: {effect_type}");
        }
        if effect_type in approval_effects and not requires_approval {
            raise ValueError(
                f"External effect {effect_type} must require approval every run"
            );
        }
        stored_effects.append({
            "type": effect_type,
            "description": str(effect.get("description", "")).strip(),
            "requiresApproval": requires_approval,
        });
    }
    validation_value: any = raw.get("validation", {});
    if not isinstance(validation_value, dict) {
        raise ValueError("Tool validation result must be an object");
    }
    validation: dict = validation_value as dict;
    if str(validation.get("status", "")) not in {"validated", "compiled"} {
        raise ValueError("Only natively validated tool programs can be published");
    }
    test_status: str = str(raw.get("testStatus", "untested"));
    if test_status not in {"untested", "connected", "passed", "failed"} {
        raise ValueError(f"Unsupported tool test status: {test_status}");
    }
    risk: str = str(raw.get("risk", "medium"));
    if risk not in {"low", "medium", "high"} {
        raise ValueError(f"Unsupported tool risk: {risk}");
    }
    return {
        "id": tool_id,
        "version": version,
        "fingerprint": _sha256_fingerprint(
            str(raw.get("fingerprint", ""))
        ),
        "name": name,
        "description": description,
        "sourcePrompt": str(raw.get("sourcePrompt", ""))[:2000],
        "target": {
            "applicationName": application_name,
            "bundleId": bundle_id,
            "processName": process_name,
            "observedVersion": str(target.get("observedVersion", "")),
            "automationMode": automation_mode,
        },
        "inputs": stored_inputs,
        "program": stored_program,
        "effects": stored_effects,
        "permissions": [str(item) for item in (raw.get("permissions", []) as list)],
        "risk": risk,
        "validation": validation,
        "testStatus": test_status,
        "createdAt": int(raw.get("createdAt", int(time()))),
    };
}


def tool_record_path(tool_id: str, base_dir: str = "") -> str {
    return os.path.join(
        data_dir("generated-tools", base_dir),
        safe_tool_id(tool_id) + ".json",
    );
}


def app_tool_record_from_data(data: dict) -> AppToolRecord {
    return AppToolRecord(
        tool_id=safe_tool_id(str(data.get("id", ""))),
        name=str(data.get("name", "")),
        description=str(data.get("description", "")),
        archived=bool(data.get("archived", False)),
        latest_version=int(data.get("latestVersion", 1)),
        created_at=int(data.get("createdAt", 0)),
        updated_at=int(data.get("updatedAt", 0)),
        archived_at=int(data.get("archivedAt", 0)),
        versions=data.get("versions", []) as list[dict],
    );
}


def _allocate_tool_id(base_dir: str = "") -> str {
    stamp: int = int(time() * 1000);
    for number in range(1, 10001) {
        candidate: str = (
            f"tool-{stamp}" if number == 1 else f"tool-{stamp}-{number}"
        );
        if not os.path.exists(tool_record_path(candidate, base_dir)) {
            return candidate;
        }
    }
    raise RuntimeError("Could not allocate a generated tool ID");
}


def create_app_tool(version_data: dict, base_dir: str = "") -> AppToolRecord {
    requested_id: str = str(version_data.get("id", "")).strip();
    tool_id: str = safe_tool_id(
        requested_id if requested_id else _allocate_tool_id(base_dir)
    );
    prepared: dict = {**version_data, "id": tool_id, "version": 1};
    version: dict = _tool_version_for_storage(prepared, tool_id, 1);
    now: int = int(time());
    record = AppToolRecord(
        tool_id=tool_id,
        name=str(version["name"]),
        description=str(version["description"]),
        latest_version=1,
        created_at=now,
        updated_at=now,
        versions=[version],
    );
    if not create_json_file(tool_record_path(tool_id, base_dir), record.to_dict()) {
        raise ValueError(f"Generated tool already exists: {tool_id}");
    }
    print(f"[Swirl][Jac][Tool] created id={tool_id} version=1 status=untested");
    return record;
}


def load_app_tool(tool_id: str, base_dir: str = "") -> AppToolRecord {
    file_path: str = tool_record_path(tool_id, base_dir);
    if not os.path.exists(file_path) {
        raise ValueError(f"Generated tool not found: {tool_id}");
    }
    with open(file_path, "r", encoding="utf-8") as handle {
        record = app_tool_record_from_data(json.load(handle) as dict);
    }
    if record.tool_id != safe_tool_id(tool_id) {
        raise ValueError("Generated tool ID conflicts with its storage path");
    }
    return record;
}


def app_tool_version(record: AppToolRecord, version: int = 0) -> dict {
    requested: int = version if version > 0 else record.latest_version;
    for item in record.versions {
        if int(item.get("version", 0)) == requested {
            return item;
        }
    }
    raise ValueError(
        f"Generated tool {record.tool_id} has no version {requested}"
    );
}


def list_app_tools(
    base_dir: str = "",
    include_archived: bool = False,
) -> list[AppToolRecord] {
    directory: str = data_dir("generated-tools", base_dir);
    records: list[AppToolRecord] = [];
    for file_name in os.listdir(directory) {
        if not file_name.endswith(".json") {
            continue;
        }
        with open(
            os.path.join(directory, file_name), "r", encoding="utf-8"
        ) as handle {
            record = app_tool_record_from_data(json.load(handle) as dict);
        }
        if include_archived or not record.archived {
            records.append(record);
        }
    }
    records.sort(
        key=lambda (record: AppToolRecord) { record.updated_at; },
        reverse=True,
    );
    return records;
}


def publish_app_tool_version(
    tool_id: str,
    version_data: dict,
    base_dir: str = "",
) -> AppToolRecord {
    record: AppToolRecord = load_app_tool(tool_id, base_dir);
    if record.archived {
        raise ValueError("Archived tools cannot publish new versions");
    }
    next_version: int = record.latest_version + 1;
    prepared: dict = {
        **version_data,
        "id": record.tool_id,
        "version": next_version,
    };
    version: dict = _tool_version_for_storage(
        prepared, record.tool_id, next_version
    );
    record.versions.append(version);
    record.latest_version = next_version;
    record.name = str(version["name"]);
    record.description = str(version["description"]);
    record.updated_at = int(time());
    atomic_json_write(tool_record_path(record.tool_id, base_dir), record.to_dict());
    print(
        f"[Swirl][Jac][Tool] published id={record.tool_id} "
        f"version={next_version} status=untested"
    );
    return record;
}


def archive_app_tool(tool_id: str, base_dir: str = "") -> bool {
    record: AppToolRecord = load_app_tool(tool_id, base_dir);
    if record.archived {
        return False;
    }
    now: int = int(time());
    record.archived = True;
    record.archived_at = now;
    record.updated_at = now;
    atomic_json_write(tool_record_path(record.tool_id, base_dir), record.to_dict());
    print(f"[Swirl][Jac][Tool] archived id={record.tool_id}");
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


test "storage preserves every node position" {
    workflow = {
        "nodes": [
            {
                "id": "workflow-source",
                "type": "source",
                "title": "Source",
                "category": "source",
                "x": 32,
                "y": 140,
                "config": {},
            },
            {
                "id": "discord-agent",
                "type": "mac_app_agent",
                "title": "Discord Agent",
                "category": "mac",
                "position": {"x": 612.5, "y": 284.25},
                "config": {
                    "application": "Discord",
                    "prompt": "Send a message",
                    "preparedScript": "tell application \"Discord\"",
                },
            },
        ],
        "edges": [{
            "id": "source-agent",
            "source": "workflow-source",
            "target": "discord-agent",
        }],
    };
    with tempfile.TemporaryDirectory() as directory {
        created = create_workflow("Position Test", workflow, directory);
        loaded = load_workflow(created.name, directory);
        assert loaded.workflow["nodes"][0]["position"]["x"] == 32.0;
        assert loaded.workflow["nodes"][0]["position"]["y"] == 140.0;
        assert loaded.workflow["nodes"][1]["position"]["x"] == 612.5;
        assert loaded.workflow["nodes"][1]["position"]["y"] == 284.25;
        assert "preparedScript" not in loaded.workflow["nodes"][1]["config"];
    }
}


def sample_app_tool_version(
    tool_id: str = "tool-discord",
    fingerprint: str = "a" * 64,
) -> dict {
    return {
        "id": tool_id,
        "version": 1,
        "fingerprint": fingerprint,
        "name": "Send Discord DM",
        "description": "Send a direct message to one Discord recipient.",
        "sourcePrompt": "Make a tool to text my friend on Discord",
        "target": {
            "applicationName": "Discord",
            "bundleId": "com.hnc.Discord",
            "processName": "Discord",
            "observedVersion": "1.0",
            "automationMode": "accessibility",
        },
        "inputs": [
            {
                "key": "recipient", "label": "Recipient",
                "inputType": "string", "required": True,
                "defaultValue": "", "sensitive": True,
            },
            {
                "key": "message", "label": "Message",
                "inputType": "string", "required": True,
                "defaultValue": "", "sensitive": True,
            },
        ],
        "program": [
            {"op": "activate_app"},
            {"op": "wait_frontmost"},
            {"op": "type_input", "inputKey": "message"},
        ],
        "effects": [{
            "type": "send", "description": "Sends one Discord message",
            "requiresApproval": True,
        }],
        "permissions": ["Automation", "Accessibility"],
        "risk": "medium",
        "validation": {
            "status": "validated", "validatedBy": "rust-safe-ir-v1"
        },
        "testStatus": "untested",
    };
}


test "generated tool CRUD preserves immutable versions and archive history" {
    with tempfile.TemporaryDirectory() as directory {
        created = create_app_tool(sample_app_tool_version(), directory);
        assert created.latest_version == 1;
        assert not created.archived;
        assert len(list_app_tools(directory)) == 1;
        assert app_tool_version(created)["testStatus"] == "untested";

        next_version: dict = sample_app_tool_version(
            "tool-discord", "b" * 64
        );
        next_version["description"] = "Send a reviewed Discord direct message.";
        published = publish_app_tool_version(
            created.tool_id, next_version, directory
        );
        assert published.latest_version == 2;
        assert app_tool_version(published, 1)["fingerprint"] == "a" * 64;
        assert app_tool_version(published, 2)["fingerprint"] == "b" * 64;

        assert archive_app_tool(created.tool_id, directory);
        assert len(list_app_tools(directory)) == 0;
        archived = load_app_tool(created.tool_id, directory);
        assert archived.archived;
        assert app_tool_version(archived, 1)["name"] == "Send Discord DM";
    }
}


test "generated tool workflow storage keeps pins and positions but redacts private bindings" {
    fingerprint: str = "c" * 64;
    snapshot: dict = sample_app_tool_version("tool-discord", fingerprint);
    workflow: dict = {
        "nodes": [
            {
                "id": "workflow-source",
                "type": "source",
                "title": "On Run Button",
                "category": "source",
                "position": {"x": 32.0, "y": 140.0},
                "config": {
                    "eventType": "trigger_manual",
                    "runMode": "once",
                },
            },
            {
                "id": "discord-tool",
                "type": "generated_app_tool",
                "title": "Send Discord DM",
                "category": "mac",
                "position": {"x": 612.5, "y": 284.25},
                "toolRef": {
                    "id": "tool-discord",
                    "version": 1,
                    "fingerprint": fingerprint,
                },
                "toolSnapshot": snapshot,
                "config": {
                    "bindings": {
                        "recipient": {
                            "kind": "literal",
                            "value": "Private recipient",
                        },
                        "message": {
                            "kind": "context",
                            "path": "text",
                        },
                    },
                    "preparedScript": "must never persist",
                    "approvalToken": "must never persist",
                },
            },
        ],
        "edges": [{
            "id": "source-discord",
            "source": "workflow-source",
            "target": "discord-tool",
        }],
    };
    with tempfile.TemporaryDirectory() as directory {
        created = create_workflow("Pinned Tool Storage", workflow, directory);
        loaded = load_workflow(created.name, directory);
        stored: dict = loaded.workflow["nodes"][1] as dict;
        assert stored["position"] == {"x": 612.5, "y": 284.25};
        assert stored["toolRef"] == {
            "id": "tool-discord",
            "version": 1,
            "fingerprint": fingerprint,
        };
        assert stored["toolSnapshot"]["target"]["bundleId"] == "com.hnc.Discord";
        assert stored["config"]["bindings"]["recipient"]["value"] == "";
        assert stored["config"]["bindings"]["message"]["path"] == "text";
        assert "preparedScript" not in stored["config"];
        assert "approvalToken" not in stored["config"];
    }
}
