"""Pure workflow validation and reordering."""

import from contracts {
    BlockDefinitionSpec,
    BlockSpec,
    ConnectionSpec,
    ValidationResult,
    WorkflowSpec
}
import from block_registry {
    block_definition,
    default_connector_names,
    supported_block_types
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
    definition = block_definition(block_type);
    return (
        [port.name for port in definition.input_ports]
            if definition is not None
            else []
    );
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
    supported_types = supported_block_types();
    if len(workflow.blocks) != len(supported_types) {
        _add_error(errors, "Workflow must contain exactly the seven golden blocks.");
    }
    type_counts: dict[str, int] = {};
    for supported_type in supported_types {
        type_counts[supported_type] = 0;
    }
    for block in workflow.blocks {
        if block.block_type not in supported_types {
            _add_error(errors, f"Unsupported block type: {block.block_type}.");
            continue;
        }
        candidate_definition = block_definition(block.block_type);
        if candidate_definition is None {
            _add_error(errors, f"Missing registry definition: {block.block_type}.");
            continue;
        }
        definition: BlockDefinitionSpec = candidate_definition;
        if block.block_version != definition.version {
            _add_error(
                errors,
                f"Block {block.id} must use block version {definition.version}."
            );
        }
        if block.config_version != definition.config_version {
            _add_error(
                errors,
                f"Block {block.id} must use config version {definition.config_version}."
            );
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
        for requirement in definition.connector_requirements {
            if requirement.connector_id not in available_connectors {
                message = (
                    f"Connector {requirement.connector_id} required by block "
                    f"{block.id} is unavailable."
                );
                if requirement.required {
                    _add_error(errors, message);
                } elif message not in warnings {
                    warnings.append(message);
                }
            }
        }
        allowed_config_keys = [field.key for field in definition.config_schema];
        for config_key in block.config {
            if config_key not in allowed_config_keys {
                _add_error(
                    errors,
                    f"Block {block.id} has undeclared config key {config_key}."
                );
            }
        }
        for field in definition.config_schema {
            value = _config_string(block, field.key);
            if field.required and not value {
                _add_error(
                    errors, f"Block {block.id} requires config field {field.key}."
                );
            }
            if field.allowed_values and value not in field.allowed_values {
                _add_error(
                    errors,
                    (
                        f"Block {block.id} config {field.key} must be one of "
                        + ", ".join(field.allowed_values) + "."
                    )
                );
            }
        }
    }
    for supported_type in supported_types {
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
        source_block = block_by_id[connection.source_id];
        target_block = block_by_id[connection.target_id];
        if connection.source_port not in source_block.outputs {
            _add_error(
                errors,
                (
                    f"Connection {connection.source_id}->{connection.target_id} "
                    f"uses unknown source port {connection.source_port}."
                )
            );
        }
        if connection.target_port not in target_block.inputs {
            _add_error(
                errors,
                (
                    f"Connection {connection.source_id}->{connection.target_id} "
                    f"uses unknown target port {connection.target_port}."
                )
            );
        }
        if connection.source_port != connection.target_port {
            _add_error(
                errors,
                (
                    f"Connection {connection.source_id}->{connection.target_id} "
                    "has incompatible ports."
                )
            );
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
        source_port = blocks[position].outputs[0] if blocks[position].outputs else "";
        connections.append(
            ConnectionSpec(
                source_id=blocks[position].id,
                target_id=blocks[position + 1].id,
                source_port=source_port,
                target_port=source_port
            )
        );
    }
    candidate = WorkflowSpec(
        id=workflow.id,
        name=workflow.name,
        version=workflow.version,
        blocks=blocks,
        connections=connections,
        validation=ValidationResult(),
        compiler_provenance=workflow.compiler_provenance
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
