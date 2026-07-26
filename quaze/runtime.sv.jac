"""Pure workflow validation/reordering and connector-result execution helpers."""

import from contracts {
    BlockSpec,
    ConnectionSpec,
    ConnectorResult,
    ValidationResult,
    WorkflowSpec
}
import from connectors {
    BRIEF_FILENAME,
    CalendarEvent,
    VaultNote,
    draft_brief,
    events_from_result,
    markdown_from_result,
    notes_from_result,
    open_saved_brief,
    read_calendar,
    save_brief,
    search_vault,
    source_references_from_result
}


glob SUPPORTED_BLOCK_TYPES: list[str] = [
         "run_now",
         "read_calendar",
         "search_vault",
         "draft_brief",
         "approval",
         "save_brief",
         "open_result"
     ];
glob DEFAULT_CONNECTORS: list[str] = [
         "calendar",
         "vault",
         "filesystem",
         "obsidian"
     ];


obj RuntimeExecutionResult {
    has success: bool = False,
        state: str = "idle",
        validation: ValidationResult = ValidationResult(),
        meetings: list[CalendarEvent] = [],
        notes: list[VaultNote] = [],
        draft_markdown: str = "",
        source_references: list[str] = [],
        artifact_path: str = "",
        artifact_hash: str = "",
        artifact_created: bool = False,
        save_called: bool = False,
        evidence: list[str] = [],
        error: str = "";
}


def default_connector_names -> list[str] {
    return [name for name in DEFAULT_CONNECTORS];
}


def _add_error(errors: list[str], message: str) {
    if message not in errors {
        errors.append(message);
    }
}


def _config_string(block: BlockSpec, key: str) -> str {
    value = block.config.get(key);
    if isinstance(value, str) {
        return value;
    }
    return "";
}


def _required_inputs(block_type: str) -> list[str] {
    if block_type == "read_calendar" {
        return ["run_request"];
    }
    if block_type == "search_vault" {
        return ["meetings"];
    }
    if block_type == "draft_brief" {
        return ["meetings", "matched_notes"];
    }
    if block_type == "approval" {
        return ["brief_markdown"];
    }
    if block_type == "save_brief" {
        return ["approved_brief"];
    }
    if block_type == "open_result" {
        return ["artifact"];
    }
    return [];
}


def _required_connector(block_type: str) -> str {
    if block_type == "read_calendar" {
        return "calendar";
    }
    if block_type == "search_vault" {
        return "vault";
    }
    if block_type == "save_brief" {
        return "filesystem";
    }
    if block_type == "open_result" {
        return "obsidian";
    }
    return "";
}


def _safe_block_map(workflow: WorkflowSpec, errors: list[str]) -> dict[str, BlockSpec] {
    block_by_id: dict[str, BlockSpec] = {};
    for block in workflow.blocks {
        stable_id = block.id.strip();
        if not stable_id {
            _add_error(errors, "Every block must have a non-empty stable ID.");
            continue;
        }
        if stable_id in block_by_id {
            _add_error(errors, f"Duplicate stable block ID: {stable_id}.");
            continue;
        }
        block_by_id[stable_id] = block;
    }
    return block_by_id;
}


def _validate_block_set(
    workflow: WorkflowSpec,
    available_connectors: list[str],
    errors: list[str],
    warnings: list[str]
) {
    if len(workflow.blocks) != len(SUPPORTED_BLOCK_TYPES) {
        _add_error(errors, "Workflow must contain exactly the seven golden blocks.");
    }
    type_counts: dict[str, int] = {};
    for supported_type in SUPPORTED_BLOCK_TYPES {
        type_counts[supported_type] = 0;
    }
    for block in workflow.blocks {
        if block.block_type not in SUPPORTED_BLOCK_TYPES {
            _add_error(errors, f"Unsupported block type: {block.block_type}.");
            continue;
        }
        type_counts[block.block_type] = type_counts[block.block_type] + 1;
        for required_input in _required_inputs(block.block_type) {
            if required_input not in block.inputs {
                _add_error(
                    errors,
                    (
                        f"Block {block.id} is missing required input "
                        f"{required_input}."
                    )
                );
            }
        }
        connector_name = _required_connector(block.block_type);
        if connector_name and connector_name not in available_connectors {
            _add_error(
                errors,
                (
                    f"Connector {connector_name} required by block "
                    f"{block.id} is unavailable."
                )
            );
        }

        if block.block_type == "read_calendar" {
            if _config_string(block, "calendar") != "QuaZe Demo" {
                _add_error(
                    errors, "Read Calendar must target only the QuaZe Demo calendar."
                );
            }
            if _config_string(block, "range") != "tomorrow" {
                _add_error(
                    errors, "Read Calendar must use the bounded tomorrow range."
                );
            }
        } elif block.block_type == "search_vault" {
            if _config_string(block, "vault") != "fixtures/demo-vault" {
                _add_error(
                    errors, "Search Vault must target only fixtures/demo-vault."
                );
            }
        } elif block.block_type == "save_brief" {
            if _config_string(block, "filename") != BRIEF_FILENAME {
                _add_error(errors, f"Save Brief may write only {BRIEF_FILENAME}.");
            }
        }
    }
    for supported_type in SUPPORTED_BLOCK_TYPES {
        count = type_counts[supported_type];
        if count == 0 {
            _add_error(
                errors, f"Workflow is missing required block type: {supported_type}."
            );
        }
        if count > 1 {
            _add_error(
                errors, f"Workflow contains duplicate block type: {supported_type}."
            );
        }
    }
    if "obsidian" not in available_connectors {
        warnings.append(
            "Obsidian is unavailable; the saved artifact cannot be opened."
        );
    }
}


def _valid_connections(
    workflow: WorkflowSpec, block_by_id: dict[str, BlockSpec], errors: list[str]
) -> list[ConnectionSpec] {
    connections: list[ConnectionSpec] = [];
    seen_connections: set[str] = set();
    for connection in workflow.connections {
        if connection.source_id not in block_by_id {
            _add_error(
                errors,
                ("Connection source does not exist: " + connection.source_id + ".")
            );
            continue;
        }
        if connection.target_id not in block_by_id {
            _add_error(
                errors,
                ("Connection target does not exist: " + connection.target_id + ".")
            );
            continue;
        }
        connection_key = connection.source_id + "->" + connection.target_id;
        if connection_key in seen_connections {
            _add_error(errors, "Duplicate connection: " + connection_key + ".");
            continue;
        }
        seen_connections.add(connection_key);
        connections.append(connection);
    }
    return connections;
}


def _validate_graph(
    workflow: WorkflowSpec,
    block_by_id: dict[str, BlockSpec],
    connections: list[ConnectionSpec],
    errors: list[str]
) {
    if len(workflow.connections) != max(len(workflow.blocks) - 1, 0) {
        _add_error(
            errors,
            "The workflow must be a linear chain with one fewer connection than blocks."
        );
    }
    adjacency: dict[str, list[str]] = {};
    incoming: dict[str, list[str]] = {};
    in_degree: dict[str, int] = {};
    for stable_id in block_by_id {
        adjacency[stable_id] = [];
        incoming[stable_id] = [];
        in_degree[stable_id] = 0;
    }
    for connection in connections {
        adjacency[connection.source_id].append(connection.target_id);
        incoming[connection.target_id].append(connection.source_id);
        in_degree[connection.target_id] = in_degree[connection.target_id] + 1;
    }

    for stable_id in block_by_id {
        block = block_by_id[stable_id];
        expected_incoming = 0 if block.block_type == "run_now" else 1;
        expected_outgoing = 0 if block.block_type == "open_result" else 1;
        if len(incoming[stable_id]) != expected_incoming {
            _add_error(
                errors,
                (
                    f"Block {stable_id} must have {expected_incoming} incoming "
                    "connection(s)."
                )
            );
        }
        if len(adjacency[stable_id]) != expected_outgoing {
            _add_error(
                errors,
                (
                    f"Block {stable_id} must have {expected_outgoing} outgoing "
                    "connection(s)."
                )
            );
        }
    }

    queue: list[str] = [
        stable_id
        for stable_id in block_by_id
        if in_degree[stable_id] == 0
    ];
    processed = 0;
    while queue {
        current = queue.pop(0);
        processed += 1;
        for target_id in adjacency[current] {
            in_degree[target_id] = in_degree[target_id] - 1;
            if in_degree[target_id] == 0 {
                queue.append(target_id);
            }
        }
    }
    if processed != len(block_by_id) {
        _add_error(errors, "Workflow contains a cycle.");
    }

    start_ids = [
        block.id
        for block in workflow.blocks
        if block.block_type == "run_now" and block.id in block_by_id
    ];
    if len(start_ids) == 1 {
        reachable: set[str] = set();
        pending: list[str] = [start_ids[0]];
        while pending {
            current = pending.pop(0);
            if current in reachable {
                continue;
            }
            reachable.add(current);
            for target_id in adjacency[current] {
                if target_id not in reachable {
                    pending.append(target_id);
                }
            }
        }
        unreachable = [
            block.id
            for block in workflow.blocks
            if block.id in block_by_id and block.id not in reachable
        ];
        if unreachable {
            _add_error(
                errors, "Unreachable workflow steps: " + ", ".join(unreachable) + "."
            );
        }

        available_outputs: set[str] = set();
        checked_path: set[str] = set();
        current_id = start_ids[0];
        while current_id not in checked_path {
            checked_path.add(current_id);
            current_block = block_by_id[current_id];
            for required_input in current_block.inputs {
                if required_input not in available_outputs {
                    _add_error(
                        errors,
                        (
                            f"Block {current_id} input {required_input} is "
                            "unavailable before execution."
                        )
                    );
                }
            }
            for output_name in current_block.outputs {
                available_outputs.add(output_name);
            }
            if len(adjacency[current_id]) != 1 {
                break;
            }
            current_id = adjacency[current_id][0];
        }
    }

    for block in workflow.blocks {
        if block.block_type != "save_brief" or block.id not in incoming {
            continue;
        }
        predecessors = incoming[block.id];
        if (
            len(predecessors) != 1
            or block_by_id[predecessors[0]].block_type != "approval"
        ) {
            _add_error(errors, "Save Brief must be immediately preceded by Approval.");
        }
    }
}


def validate_workflow_spec(
    workflow: WorkflowSpec, available_connectors: list[str] | None = None
) -> ValidationResult {
    connector_names = (
        default_connector_names()
            if available_connectors is None
            else available_connectors
    );
    errors: list[str] = [];
    warnings: list[str] = [];
    block_by_id = _safe_block_map(workflow, errors);
    _validate_block_set(workflow, connector_names, errors, warnings);
    connections = _valid_connections(workflow, block_by_id, errors);
    _validate_graph(workflow, block_by_id, connections, errors);
    return ValidationResult(valid=not errors, errors=errors, warnings=warnings);
}


def _rebuilt_workflow(
    workflow: WorkflowSpec, blocks: list[BlockSpec], available_connectors: list[str]
) -> WorkflowSpec {
    connections: list[ConnectionSpec] = [];
    for position in range(len(blocks) - 1) {
        connections.append(
            ConnectionSpec(
                source_id=blocks[position].id, target_id=blocks[position + 1].id
            )
        );
    }
    candidate = WorkflowSpec(
        id=workflow.id,
        name=workflow.name,
        version=workflow.version,
        blocks=blocks,
        connections=connections,
        validation=ValidationResult()
    );
    candidate.validation = validate_workflow_spec(candidate, available_connectors);
    return candidate;
}


def reorder_workflow_spec(
    workflow: WorkflowSpec,
    block_id: str,
    direction: str,
    available_connectors: list[str] | None = None
) -> WorkflowSpec {
    connector_names = (
        default_connector_names()
            if available_connectors is None
            else available_connectors
    );
    blocks = [block for block in workflow.blocks];
    block_index = -1;
    for position in range(len(blocks)) {
        if blocks[position].id == block_id {
            block_index = position;
            break;
        }
    }
    if block_index < 0 {
        candidate = _rebuilt_workflow(workflow, blocks, connector_names);
        candidate.validation.valid = False;
        _add_error(
            candidate.validation.errors, f"Cannot reorder unknown block ID: {block_id}."
        );
        return candidate;
    }
    if direction not in ["up", "down"] {
        candidate = _rebuilt_workflow(workflow, blocks, connector_names);
        candidate.validation.valid = False;
        _add_error(
            candidate.validation.errors, "Reorder direction must be up or down."
        );
        return candidate;
    }
    target_index = block_index - 1 if direction == "up" else block_index + 1;
    if target_index >= 0 and target_index < len(blocks) {
        moved = blocks[block_index];
        blocks[block_index] = blocks[target_index];
        blocks[target_index] = moved;
    }
    return _rebuilt_workflow(workflow, blocks, connector_names);
}


def _failed_execution(
    validation: ValidationResult,
    meetings: list[CalendarEvent] | None = None,
    notes: list[VaultNote] | None = None,
    evidence: list[str] | None = None,
    error: str = "",
    save_called: bool = False
) -> RuntimeExecutionResult {
    return RuntimeExecutionResult(
        success=False,
        state="failed",
        validation=validation,
        meetings=[] if meetings is None else meetings,
        notes=[] if notes is None else notes,
        save_called=save_called,
        evidence=[] if evidence is None else evidence,
        error=error
    );
}


def prepare_run(
    workflow: WorkflowSpec,
    calendar_result: ConnectorResult,
    vault_result: ConnectorResult,
    available_connectors: list[str] | None = None
) -> RuntimeExecutionResult {
    validation = validate_workflow_spec(workflow, available_connectors);
    if not validation.valid {
        return _failed_execution(
            validation=validation,
            error="Workflow validation failed before connector execution."
        );
    }
    evidence: list[str] = [];
    if calendar_result.evidence_summary {
        evidence.append(calendar_result.evidence_summary);
    }
    if not calendar_result.success {
        return _failed_execution(
            validation=validation, evidence=evidence, error=calendar_result.error
        );
    }
    meetings = events_from_result(calendar_result);
    if not meetings {
        return _failed_execution(
            validation=validation,
            evidence=evidence,
            error="Calendar connector returned no usable events."
        );
    }
    if vault_result.evidence_summary {
        evidence.append(vault_result.evidence_summary);
    }
    if not vault_result.success {
        return _failed_execution(
            validation=validation,
            meetings=meetings,
            evidence=evidence,
            error=vault_result.error
        );
    }
    notes = notes_from_result(vault_result);
    draft_result = draft_brief(meetings, notes);
    if draft_result.evidence_summary {
        evidence.append(draft_result.evidence_summary);
    }
    if not draft_result.success {
        return _failed_execution(
            validation=validation,
            meetings=meetings,
            notes=notes,
            evidence=evidence,
            error=draft_result.error
        );
    }
    return RuntimeExecutionResult(
        success=True,
        state="awaiting_approval",
        validation=validation,
        meetings=meetings,
        notes=notes,
        draft_markdown=markdown_from_result(draft_result),
        source_references=source_references_from_result(draft_result),
        save_called=False,
        evidence=evidence
    );
}


def run_to_approval(
    workflow: WorkflowSpec,
    connector_mode: str = "fixture",
    available_connectors: list[str] | None = None,
    reference_date: str = "",
    calendar_available: bool = True,
    vault_available: bool = True
) -> RuntimeExecutionResult {
    validation = validate_workflow_spec(workflow, available_connectors);
    if not validation.valid {
        return _failed_execution(
            validation=validation,
            error="Workflow validation failed before connector execution."
        );
    }
    calendar_result = read_calendar(
        connector_mode=connector_mode,
        reference_date=reference_date,
        available=calendar_available
    );
    if not calendar_result.success {
        return prepare_run(
            workflow,
            calendar_result,
            ConnectorResult(
                success=False,
                evidence_summary="not called: Calendar failed first.",
                error="Vault connector was not called."
            ),
            available_connectors
        );
    }
    meetings = events_from_result(calendar_result);
    vault_mode = "fixture" if connector_mode == "fixture" else "mcp";
    vault_result = search_vault(
        meetings=meetings,
        connector_mode=vault_mode,
        available=vault_available,
        allow_fallback=True
    );
    return prepare_run(workflow, calendar_result, vault_result, available_connectors);
}


def _saved_string(saved: ConnectorResult, key: str) -> str {
    value = saved.data.get(key);
    if isinstance(value, str) {
        return value;
    }
    return "";
}


def _saved_bool(saved: ConnectorResult, key: str) -> bool {
    value = saved.data.get(key);
    if isinstance(value, bool) {
        return value;
    }
    return False;
}


def resume_approved_run(
    prepared: RuntimeExecutionResult, approved: bool, launch_result: bool = False
) -> RuntimeExecutionResult {
    if not prepared.success
    or prepared.state not in ["awaiting_approval", "succeeded"] {
        return _failed_execution(
            validation=prepared.validation,
            meetings=prepared.meetings,
            notes=prepared.notes,
            evidence=[entry for entry in prepared.evidence],
            error="Only a prepared run can be resumed."
        );
    }
    if not approved {
        return _failed_execution(
            validation=prepared.validation,
            meetings=prepared.meetings,
            notes=prepared.notes,
            evidence=[entry for entry in prepared.evidence],
            error="Approval was rejected; Save Brief was not called."
        );
    }
    evidence = [entry for entry in prepared.evidence];
    saved = save_brief(prepared.draft_markdown, prepared.source_references);
    if saved.evidence_summary {
        evidence.append(saved.evidence_summary);
    }
    if not saved.success {
        return _failed_execution(
            validation=prepared.validation,
            meetings=prepared.meetings,
            notes=prepared.notes,
            evidence=evidence,
            error=saved.error,
            save_called=True
        );
    }
    if launch_result {
        opened = open_saved_brief(launch_gui=True);
        if opened.evidence_summary {
            evidence.append(opened.evidence_summary);
        }
        if not opened.success {
            evidence.append("Open Result error: " + opened.error);
        }
    } else {
        evidence.append("unavailable: Obsidian launch was not requested for this run.");
    }
    return RuntimeExecutionResult(
        success=True,
        state="succeeded",
        validation=prepared.validation,
        meetings=prepared.meetings,
        notes=prepared.notes,
        draft_markdown=prepared.draft_markdown,
        source_references=prepared.source_references,
        artifact_path=_saved_string(saved, "path"),
        artifact_hash=_saved_string(saved, "content_hash"),
        artifact_created=_saved_bool(saved, "created"),
        save_called=True,
        evidence=evidence
    );
}
