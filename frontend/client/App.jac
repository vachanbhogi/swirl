"""Stateful Jac client shell for the Swirl desktop workflow editor."""

import from react { useEffect }
import from .Navbar { Navbar }
import from .WhiteboardCard { WhiteboardCard }
import from .CodeBlockPalette { CodeBlockPalette }
import from .NodePropertiesPanel { NodePropertiesPanel }
import from .AIScreen { AIScreen }
import from .WorkflowsScreen { WorkflowsScreen }
import from .ExecutionInspector { ExecutionInspector }
import from .data {
    BLOCK_CATEGORIES,
    BLOCK_LIBRARY,
    SOURCE_EVENTS,
    INITIAL_NODES,
    INITIAL_EDGES,
    change_source_event,
    generated_tool_palette_block,
    normalize_workflow,
    suggest_generated_workflow_name,
    trigger_block_library,
}
import from .native_bridge {
    compile_workflow_prompt,
    create_workflow,
    save_workflow,
    load_workflow,
    list_workflows,
    delete_workflow,
    is_tauri_environment,
    listen_to_workflow_events,
    list_generated_tools,
    archive_generated_tool,
    check_generated_tool,
    resolve_workflow_approval,
    start_workflow,
    stop_workflow,
}

glob AUTO_SAVE_DELAY_MS: int = 2000;


def local_time -> str {
    date_constructor: any = Date;  # jac:ignore[W2001]
    date_value: any = new(date_constructor);
    return str(date_value.toLocaleTimeString());
}


def timestamp_ms -> int {
    date_constructor: any = Date;  # jac:ignore[W2001]
    date_value: any = new(date_constructor);
    return int(date_value.getTime());
}


def generated_tool_block(record: dict) -> dict {
    return generated_tool_palette_block(record);
}


def:pub SwirlApp -> JsxElement {
    has nodes: list = normalize_workflow(
        INITIAL_NODES, INITIAL_EDGES
    )["nodes"] as list;
    has edges: list = normalize_workflow(
        INITIAL_NODES, INITIAL_EDGES
    )["edges"] as list;
    has is_executing: bool = False;
    has active_node_id: str | None = None;
    has selected_node_id: str | None = None;
    has is_compiling_prompt: bool = False;
    has compile_status: dict = {"type": "idle", "message": ""};
    has active_run: dict | None = None;
    has is_stopping: bool = False;
    has logs: list[dict] = [];
    has execution_results: dict = {};
    has active_tab: str = "workflow";
    has show_logs_inspector: bool = False;
    has editing_workflow: bool = False;
    has current_workflow_name: str | None = None;
    has saved_workflows: list = [];
    has has_unsaved_changes: bool = False;
    has is_saving: bool = False;
    has save_error: str | None = None;
    has generated_tools: list = [];
    has tool_builder_prompt: str = "";
    has approval_request: dict | None = None;
    has is_resolving_approval: bool = False;
    has tool_catalog_error: str | None = None;

    has terminal_run_ids: Ref[set[str]] = Ref(set());
    has auto_save_timer: Ref[any] = Ref(None);
    has nodes_ref: Ref[list] = Ref([]);
    has edges_ref: Ref[list] = Ref([]);
    has logs_ref: Ref[list[dict]] = Ref([]);
    has results_ref: Ref[dict] = Ref({});
    has active_run_ref: Ref[dict | None] = Ref(None);
    has current_name_ref: Ref[str | None] = Ref(None);
    has skip_next_auto_save: Ref[bool] = Ref(False);

    nodes_ref.current = nodes;
    edges_ref.current = edges;
    logs_ref.current = logs;
    results_ref.current = execution_results;
    active_run_ref.current = active_run;
    current_name_ref.current = current_workflow_name;

    def append_log(log_entry: dict) {
        next_logs: list[dict] = (logs_ref.current or []) + [log_entry];
        logs_ref.current = next_logs;
        logs = next_logs;
    }

    def set_node_status(event: any) {
        event_node_id: str = str(event.nodeId);
        next_nodes: list = [];
        for workflow_node in (nodes_ref.current or []) {
            if workflow_node["id"] == event_node_id {
                next_nodes.append(
                    {
                        **workflow_node,
                        "status": event.status or workflow_node["status"],
                        "output": event.output or workflow_node["output"],
                    }
                );
            } else {
                next_nodes.append(workflow_node);
            }
        }
        nodes_ref.current = next_nodes;
        nodes = next_nodes;
    }

    def set_result(node_id: str, output: any) {
        next_results: dict = {
            **(results_ref.current or {}),
            node_id: output,
        };
        results_ref.current = next_results;
        execution_results = next_results;
    }

    def handle_backend_event(event: any) {
        append_log({
            "time": local_time(),
            "type": (
                "error"
                if event.status == "error"
                else ("success" if event.status == "success" else "info")
            ),
            "prefix": event.event,
            "message": event.message or event.title or "Workflow event received",
        });
        if event.event == "approval_required" and event.output {
            request_value: dict = event.output as dict;
            if request_value.get("approvalId") {
                approval_request = request_value;
                is_resolving_approval = False;
            }
        }
        if event.nodeId {
            active_node_id = str(event.nodeId);
            set_node_status(event);
        }
        if (
            (event.event == "node_complete" or event.event == "triggered")
            and event.nodeId
        ) {
            set_result(str(event.nodeId), event.output);
        }
        if event.event == "complete" and event.output {
            next_results: dict = event.output.results or {};
            results_ref.current = next_results;
            execution_results = next_results;
        }
        if event.event in ["complete", "failed", "stopped"] {
            if (
                approval_request
                and (
                    not event.runId
                    or approval_request.get("runId") == event.runId
                )
            ) {
                approval_request = None;
                is_resolving_approval = False;
            }
            if event.runId and terminal_run_ids.current {
                terminal_run_ids.current.add(str(event.runId));
            }
            current_run: dict | None = active_run_ref.current;
            if (
                not current_run
                or not event.runId
                or current_run["runId"] == event.runId
            ) {
                active_run_ref.current = None;
                active_run = None;
                is_executing = False;
                is_stopping = False;
                active_node_id = None;
            }
        }
    }

    useEffect(lambda {
        cleanup: any = None;
        pending = listen_to_workflow_events(handle_backend_event);
        pending.then(lambda (unlisten: any) {
            cleanup = unlisten;
        });
        return lambda {
            if cleanup { cleanup.call(None); }
        };
    }, []);

    async def refresh_workflow_list -> None {
        if not is_tauri_environment() { return; }
        try {
            saved_workflows = await list_workflows() or [];
        } except Exception as error {
            console_object: any = console;  # jac:ignore[W2001]
            console_object.error(
                "[WorkflowManager] Failed to list workflows:",
                error,
            );
        }
    }

    async def refresh_generated_tool_list -> None {
        if not is_tauri_environment() { return; }
        try {
            generated_tools = await list_generated_tools() or [];
            tool_catalog_error = None;
        } except Exception as error {
            tool_catalog_error = str(error);
            console_object: any = console;  # jac:ignore[W2001]
            console_object.error(
                "[ToolCatalog] Failed to list generated tools:",
                error,
            );
        }
    }

    async can with entry {
        if is_tauri_environment() {
            try {
                existing: list = await list_workflows();
                if not existing {
                    starter: dict = normalize_workflow(
                        INITIAL_NODES, INITIAL_EDGES
                    );
                    _ = await save_workflow("Starter Workflow", starter);
                }
                await refresh_generated_tool_list();
            } except Exception as error {
                console_object: any = console;  # jac:ignore[W2001]
                console_object.error(
                    "[WorkflowManager] Failed to seed starter workflow:",
                    error,
                );
            }
        }
    }

    async def perform_save(
        name: str | None,
        nodes_to_save: list,
        edges_to_save: list,
    ) -> None {
        if not is_tauri_environment() or not name { return; }
        is_saving = True;
        try {
            workflow: dict = normalize_workflow(nodes_to_save, edges_to_save);
            _ = await save_workflow(name, workflow);
            has_unsaved_changes = False;
            save_error = None;
            await refresh_workflow_list();
        } except Exception as error {
            message: str = "Autosave failed: " + str(error);
            save_error = message;
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "save",
                "message": "Save failed: " + str(error),
            });
        } finally {
            is_saving = False;
        }
    }

    useEffect(lambda {
        if auto_save_timer.current {
            clearTimeout(auto_save_timer.current);  # jac:ignore[W2001,W6002]
        }
        if skip_next_auto_save.current {
            skip_next_auto_save.current = False;
            return lambda {};
        }
        if not current_workflow_name {
            return lambda {};
        }
        has_unsaved_changes = True;
        auto_save_timer.current = setTimeout(lambda {
            perform_save(
                current_name_ref.current,
                nodes_ref.current or [],
                edges_ref.current or [],
            );
        }, AUTO_SAVE_DELAY_MS);  # jac:ignore[W2001,W6002]
        return lambda {
            if auto_save_timer.current {
                clearTimeout(auto_save_timer.current);  # jac:ignore[W2001,W6002]
            }
        };
    }, [nodes, edges, current_workflow_name]);

    can with (active_tab, editing_workflow) entry {
        if active_tab == "workflow" and not editing_workflow {
            refresh_workflow_list();
        }
    }

    def handle_new_workflow {
        fresh: dict = normalize_workflow(INITIAL_NODES, INITIAL_EDGES);
        nodes = fresh["nodes"] as list;
        edges = fresh["edges"] as list;
        current_workflow_name = None;
        has_unsaved_changes = False;
        save_error = None;
        selected_node_id = None;
        logs = [];
        execution_results = {};
        editing_workflow = True;
    }

    async def handle_load_workflow(name: str) -> None {
        try {
            record = await load_workflow(name);
            if not record or not record.workflow {
                raise ValueError("Workflow record is empty.");
            }
            workflow_data: dict = record.workflow as dict;
            loaded: dict = normalize_workflow(
                workflow_data["nodes"] or [],
                workflow_data["edges"] or [],
            );
            skip_next_auto_save.current = True;
            nodes = loaded["nodes"] as list;
            edges = loaded["edges"] as list;
            current_workflow_name = str(record.name);
            has_unsaved_changes = False;
            save_error = None;
            selected_node_id = None;
            logs = [];
            execution_results = {};
            editing_workflow = True;
        } except Exception as error {
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "load",
                "message": "Failed to load \"" + name + "\": " + str(error),
            });
        }
    }

    async def handle_delete_workflow(name: str) -> None {
        try {
            _ = await delete_workflow(name);
            if current_workflow_name == name {
                current_workflow_name = None;
                has_unsaved_changes = False;
            }
            await refresh_workflow_list();
        } except Exception as error {
            console_object: any = console;  # jac:ignore[W2001]
            console_object.error(
                "[WorkflowManager] Delete failed:",
                error,
            );
        }
    }

    def handle_back_to_manager {
        editing_workflow = False;
        show_logs_inspector = False;
        selected_node_id = None;
    }

    def handle_drop_new_block(
        block_definition: dict,
        x: float,
        y: float,
    ) {
        if block_definition.get("category") == "trigger" {
            next_nodes: list = [];
            for workflow_node in nodes {
                if workflow_node.get("category") == "source" {
                    current_config: dict = workflow_node.get("config", {}) as dict;
                    next_nodes.append({
                        **workflow_node,
                        "config": change_source_event(
                            str(block_definition["type"]),
                            current_config,
                        ),
                    });
                    selected_node_id = str(workflow_node["id"]);
                } else {
                    next_nodes.append(workflow_node);
                }
            }
            nodes = next_nodes;
            return;
        }
        position: dict = {"x": x, "y": y};
        new_node: dict = {
            "id": "node-" + str(timestamp_ms()),
            "type": block_definition["type"],
            "title": block_definition["title"],
            "category": block_definition["category"],
            "jacNode": block_definition["jacNode"] or "WorkflowBlock",
            "x": x,
            "y": y,
            "position": position,
            "customPrompt": "",
            "config": {**(block_definition["config"] as dict)},
            "status": "idle",
        };
        if block_definition.get("toolRef") {
            new_node = {
                **new_node,
                "toolRef": block_definition["toolRef"],
                "toolSnapshot": block_definition["toolSnapshot"],
            };
        }
        nodes = nodes + [new_node];
        selected_node_id = str(new_node["id"]);
    }

    def handle_save_node_config(
        node_id: str,
        new_title: str,
        new_config: dict,
        custom_prompt: str | None,
    ) {
        next_nodes: list = [];
        for workflow_node in nodes {
            if workflow_node["id"] == node_id {
                next_nodes.append({
                    **workflow_node,
                    "title": new_title,
                    "config": new_config,
                    "customPrompt": (
                        custom_prompt
                        if custom_prompt is not None
                        else workflow_node["customPrompt"]
                    ),
                });
            } else {
                next_nodes.append(workflow_node);
            }
        }
        nodes = next_nodes;
    }

    def handle_duplicate_node(workflow_node: dict) {
        x: float = (workflow_node["x"] as float) + 40.0;
        y: float = (workflow_node["y"] as float) + 40.0;
        duplicate: dict = {
            **workflow_node,
            "id": "node-" + str(timestamp_ms()),
            "x": x,
            "y": y,
            "position": {"x": x, "y": y},
            "status": "idle",
        };
        nodes = nodes + [duplicate];
        selected_node_id = str(duplicate["id"]);
    }

    def handle_delete_node(node_id: str) {
        for workflow_node in nodes {
            if (
                workflow_node["id"] == node_id
                and workflow_node["category"] == "source"
            ) { return; }
        }
        nodes = [
            workflow_node
            for workflow_node in nodes
            if workflow_node["id"] != node_id
        ];
        edges = [
            edge
            for edge in edges
            if edge["source"] != node_id and edge["target"] != node_id
        ];
        if selected_node_id == node_id { selected_node_id = None; }
    }

    async def handle_run_workflow -> None {
        if not nodes or is_executing { return; }
        is_executing = True;
        execution_results = {};
        logs = [];
        try {
            if not is_tauri_environment() {
                raise RuntimeError(
                    "Run the Tauri desktop app to execute native workflows."
                );
            }
            workflow: dict = normalize_workflow(nodes, edges);
            nodes = [
                {**workflow_node, "status": "idle", "output": {}}
                for workflow_node in (workflow["nodes"] as list)
            ];
            edges = workflow["edges"] as list;
            started = await start_workflow(
                workflow,
                {},
                [],
            );
            run_id: str = str(started.runId);
            if (
                terminal_run_ids.current
                and run_id in terminal_run_ids.current
            ) {
                terminal_run_ids.current.remove(run_id);
                is_executing = False;
            } else {
                active_run = started as dict;
            }
            append_log({
                "time": local_time(),
                "type": "info",
                "prefix": "armed",
                "message": (
                    "Continuous" if started.runMode == "continuous" else "One-time"
                ) + " workflow " + run_id + " started.",
            });
        } except Exception as error {
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "error",
                "message": str(error),
            });
            is_executing = False;
            active_node_id = None;
        }
    }

    async def handle_stop_workflow -> None {
        if not active_run or not active_run["runId"] or is_stopping { return; }
        is_stopping = True;
        try {
            _ = await stop_workflow(str(active_run["runId"]));
        } except Exception as error {
            is_stopping = False;
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "stop",
                "message": str(error),
            });
        }
    }

    async def handle_resolve_approval(approved: bool) -> None {
        if not approval_request or is_resolving_approval { return; }
        is_resolving_approval = True;
        try {
            _ = await resolve_workflow_approval({
                "approvalId": approval_request["approvalId"],
                "runId": approval_request["runId"],
                "iteration": approval_request["iteration"],
                "toolFingerprint": approval_request["toolFingerprint"],
                "argumentDigest": approval_request["argumentDigest"],
                "approved": approved,
            });
            append_log({
                "time": local_time(),
                "type": "info" if approved else "error",
                "prefix": "approval",
                "message": (
                    "One-time approval granted; running the reviewed tool."
                    if approved
                    else "Tool execution cancelled with no action performed."
                ),
            });
            approval_request = None;
        } except Exception as error {
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "approval",
                "message": str(error),
            });
        } finally {
            is_resolving_approval = False;
        }
    }

    async def handle_generated_tool_saved(
        record: dict,
        add_to_canvas: bool,
    ) -> None {
        await refresh_generated_tool_list();
        # CodeBlockPalette adds the reviewed block after this callback. Keeping
        # catalog refresh here avoids inserting the same node twice.
        tool_builder_prompt = "";
        append_log({
            "time": local_time(),
            "type": "success",
            "prefix": "tool",
            "message": "Saved " + str(record.get("name", "generated tool"))
                + (" and added it to the canvas." if add_to_canvas else " to My Tools."),
        });
    }

    async def handle_archive_generated_tool(tool_value: any) -> None {
        tool_id: str = (
            str(tool_value.get("id", ""))
            if isinstance(tool_value, dict)
            else str(tool_value)
        );
        try {
            _ = await archive_generated_tool(tool_id);
            await refresh_generated_tool_list();
            append_log({
                "time": local_time(),
                "type": "info",
                "prefix": "tool",
                "message": "Archived the tool. Existing pinned blocks were kept.",
            });
        } except Exception as error {
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "tool",
                "message": str(error),
            });
        }
    }

    async def handle_check_generated_tool(tool_value: any) -> any {
        tool_id: str = (
            str(tool_value.get("id", ""))
            if isinstance(tool_value, dict)
            else str(tool_value)
        );
        try {
            result = await check_generated_tool(tool_id, None);
            append_log({
                "time": local_time(),
                "type": "success" if result.status == "ready" else "info",
                "prefix": "connection",
                "message": str(result.message or "Connection check completed without performing an action."),
            });
            return result;
        } except Exception as error {
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "connection",
                "message": str(error),
            });
            raise error;
        }
    }

    def handle_create_tool_from_prompt(prompt: str) {
        tool_builder_prompt = prompt;
        active_tab = "workflow";
        editing_workflow = True;
        selected_node_id = None;
    }

    def handle_convert_legacy_app_agent(workflow_node: dict) {
        legacy_config: dict = workflow_node.get("config", {}) as dict;
        application: str = str(legacy_config.get("application", "the selected application"));
        instruction: str = str(legacy_config.get("prompt", "perform the configured action"));
        tool_builder_prompt = "Make a tool for " + application + " that " + instruction;
        selected_node_id = None;
        append_log({
            "time": local_time(),
            "type": "info",
            "prefix": "legacy",
            "message": "Opened a safe reusable-tool draft. The legacy block remains unchanged until you replace it.",
        });
    }

    def handle_update_tool_version(node_id: str, record: dict) {
        block: dict = generated_tool_block(record);
        next_nodes: list = [];
        for workflow_node in nodes {
            if workflow_node["id"] == node_id {
                old_bindings: dict = (
                    workflow_node.get("config", {}).get("bindings", {}) as dict
                );
                next_bindings: dict = block.get("config", {}).get("bindings", {}) as dict;
                for binding_key in (Object.keys(next_bindings) as list) {  # jac:ignore[W2001,W6002]
                    if binding_key in old_bindings {
                        next_bindings[binding_key] = old_bindings[binding_key];
                    }
                }
                next_nodes.append({
                    **workflow_node,
                    "title": block["title"],
                    "toolRef": block["toolRef"],
                    "toolSnapshot": block["toolSnapshot"],
                    "config": {"bindings": next_bindings},
                    "status": "idle",
                });
            } else {
                next_nodes.append(workflow_node);
            }
        }
        nodes = next_nodes;
    }

    async def handle_generate_from_prompt(prompt: str) -> None {
        is_compiling_prompt = True;
        compile_status = {
            "type": "compiling",
            "message": "Jac AI is building your new workflow project…",
        };
        try {
            result = await compile_workflow_prompt(prompt, True);
            if not result or not result.nodes {
                raise ValueError("Jac compiler returned no workflow graph.");
            }
            workflow: dict = normalize_workflow(
                result.nodes as list,
                result.edges as list if result.edges else [],
            );
            project_name: str = suggest_generated_workflow_name(prompt);
            generator_label: str = (
                "Jac LLM" if result.source == "llm" else "Jac fast compiler"
            );
            if auto_save_timer.current {
                clearTimeout(auto_save_timer.current);  # jac:ignore[W2001,W6002]
                auto_save_timer.current = None;
            }
            current_name_ref.current = None;
            current_workflow_name = None;
            has_unsaved_changes = True;
            save_error = None;
            nodes = workflow["nodes"] as list;
            edges = workflow["edges"] as list;
            selected_node_id = None;
            execution_results = {};
            show_logs_inspector = False;
            editing_workflow = True;
            active_tab = "workflow";
            logs = [{
                "time": local_time(),
                "type": "success",
                "prefix": "compile",
                "message": "Generated " + str(len(nodes))
                    + " blocks with " + generator_label + ".",
            }];
            try {
                record = await create_workflow(project_name, workflow);
                skip_next_auto_save.current = True;
                current_name_ref.current = str(record.name);
                current_workflow_name = str(record.name);
                has_unsaved_changes = False;
                saved_workflows = [record] + [
                    workflow_record
                    for workflow_record in saved_workflows
                    if workflow_record["name"] != record.name
                ];
                compile_status = {
                    "type": "success",
                    "message": "Created \"" + str(record.name) + "\" with "
                        + str(len(nodes)) + " connected blocks using "
                        + generator_label + ".",
                };
                append_log({
                    "time": local_time(),
                    "type": "success",
                    "prefix": "project",
                    "message": "Created new workflow project \""
                        + str(record.name) + "\".",
                });
            } except Exception as save_failure {
                message: str = str(save_failure);
                save_error = "New project could not be saved: " + message;
                compile_status = {
                    "type": "error",
                    "message": "The workflow was generated, but its new project could not be saved: "
                        + message,
                };
                append_log({
                    "time": local_time(),
                    "type": "error",
                    "prefix": "project",
                    "message": "Generated workflow is unsaved: " + message,
                });
            }
        } except Exception as error {
            compile_status = {
                "type": "error",
                "message": str(error) or "Jac could not generate a valid workflow.",
            };
            append_log({
                "time": local_time(),
                "type": "error",
                "prefix": "compile",
                "message": str(error),
            });
        } finally {
            is_compiling_prompt = False;
        }
    }

    def set_nodes_from_canvas(value: list) { nodes = value; }
    def set_edges_from_canvas(value: list) { edges = value; }
    def select_node(value: str | None) { selected_node_id = value; }
    def select_tab(value: str) { active_tab = value; }
    def toggle_logs { show_logs_inspector = not show_logs_inspector; }
    def close_logs { show_logs_inspector = False; }
    def clear_logs {
        logs = [];
        execution_results = {};
    }

    selected_node: dict | None = None;
    active_node: dict | None = None;
    for workflow_node in nodes {
        if workflow_node["id"] == selected_node_id {
            selected_node = workflow_node;
        }
        if workflow_node["id"] == active_node_id {
            active_node = workflow_node;
        }
    }
    if selected_node { active_node = selected_node; }
    available_tool_updates: dict = {};
    for tool_value in generated_tools {
        tool_record: dict = tool_value as dict;
        tool_id: str = str(tool_record.get("id", ""));
        if tool_id and not bool(tool_record.get("archived", False)) {
            available_tool_updates[tool_id] = tool_record;
        }
    }
    show_editor: bool = active_tab == "workflow" and editing_workflow;
    show_manager: bool = active_tab == "workflow" and not editing_workflow;

    return <div className="h-screen w-screen flex flex-col relative overflow-hidden font-sans bg-black text-zinc-100 dark dark-theme">
        <Navbar
            key="navbar"
            active_tab={active_tab}
            set_active_tab={select_tab}
            on_run_workflow={handle_run_workflow}
            on_stop_workflow={handle_stop_workflow}
            is_executing={is_executing}
            is_stopping={is_stopping}
            active_run_mode={
                str(active_run["runMode"])
                if active_run and active_run["runMode"]
                else None
            }
            show_logs_inspector={show_logs_inspector}
            on_toggle_logs={toggle_logs}
            logs_count={len(logs)}
            current_workflow_name={current_workflow_name}
            has_unsaved_changes={has_unsaved_changes}
            is_saving={is_saving}
            save_error={save_error}
            show_back_button={show_editor}
            on_back={handle_back_to_manager}
        />

        {if show_editor {
            <div key="editor" className="flex-1 flex w-full h-full overflow-hidden p-3 gap-3 bg-black">
                <main className="flex-1 h-full relative flex flex-col rounded-2xl overflow-hidden border border-zinc-800 bg-black shadow-xl">
                    <WhiteboardCard
                        block_categories={BLOCK_CATEGORIES}
                        nodes={nodes}
                        set_nodes={set_nodes_from_canvas}
                        edges={edges}
                        set_edges={set_edges_from_canvas}
                        active_node_id={active_node_id}
                        selected_node_id={selected_node_id}
                        set_selected_node_id={select_node}
                        on_drop_new_block={handle_drop_new_block}
                    />
                </main>
                <div className="h-full rounded-2xl overflow-hidden border border-zinc-800 shadow-sm shrink-0 bg-zinc-950">
                    {if selected_node {
                        <NodePropertiesPanel
                            key="node-properties"
                            block_categories={BLOCK_CATEGORIES}
                            source_events={SOURCE_EVENTS}
                            change_source_event_handler={change_source_event}
                            selected_node={selected_node}
                            on_save_node_config={handle_save_node_config}
                            on_delete_node={handle_delete_node}
                            on_duplicate_node={handle_duplicate_node}
                            on_close={lambda { selected_node_id = None; }}
                            total_nodes={len(nodes)}
                            total_edges={len(edges)}
                            on_run_workflow={handle_run_workflow}
                            available_tool_updates={available_tool_updates}
                            on_update_tool_version={handle_update_tool_version}
                            on_convert_legacy_app_agent={handle_convert_legacy_app_agent}
                        />
                    } else {
                        <CodeBlockPalette
                            key="block-palette"
                            blocks={BLOCK_LIBRARY + trigger_block_library()}
                            on_add_block={lambda (block: dict) {
                                handle_drop_new_block(block, 260.0, 200.0);
                            }}
                            generated_tools={generated_tools}
                            tool_builder_prompt={tool_builder_prompt}
                            on_tool_builder_closed={lambda {
                                tool_builder_prompt = "";
                            }}
                            on_generated_tool_saved={handle_generated_tool_saved}
                            on_archive_generated_tool={handle_archive_generated_tool}
                            on_check_generated_tool={handle_check_generated_tool}
                        />
                    }}
                </div>
            </div>
        } elif show_manager {
            <WorkflowsScreen
                key="workflow-manager"
                saved_workflows={saved_workflows}
                current_workflow_name={current_workflow_name}
                on_new={handle_new_workflow}
                on_load={handle_load_workflow}
                on_delete={handle_delete_workflow}
                on_refresh={refresh_workflow_list}
            />
        } else {
            <AIScreen
                key="ai-builder"
                on_generate_from_prompt={handle_generate_from_prompt}
                is_compiling_prompt={is_compiling_prompt}
                on_switch_to_workflow={lambda { active_tab = "workflow"; }}
                on_create_tool_from_prompt={handle_create_tool_from_prompt}
                compile_status={compile_status}
            />
        }}

        {if show_editor {
            <ExecutionInspector
                key="execution-inspector"
                is_open={show_logs_inspector}
                on_close={close_logs}
                logs={logs}
                active_node={active_node}
                execution_results={execution_results}
                on_clear_logs={clear_logs}
            />
        }}

        {if approval_request {
            <div className="fixed inset-0 z-50 bg-black/70 flex items-end justify-center p-4 sm:p-8">
                <section
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="tool-approval-title"
                    aria-describedby="tool-approval-description"
                    className="w-full max-w-xl rounded-2xl bg-zinc-950 border border-zinc-700 p-5 text-left"
                >
                    <div className="flex items-start justify-between gap-4 pb-4 border-b border-zinc-800">
                        <div>
                            <p className="text-[11px] font-mono text-cyan-400">
                                One-time approval · iteration {approval_request.get("iteration", 1)}
                            </p>
                            <h2 id="tool-approval-title" className="mt-1 text-base font-semibold text-white">
                                Allow this tool to control {approval_request.get("application", "the selected app")}?
                            </h2>
                            <p id="tool-approval-description" className="mt-1 text-xs leading-relaxed text-zinc-400">
                                This approval is bound to this run, tool fingerprint, and resolved inputs. Values stay redacted and the approval cannot be reused.
                            </p>
                        </div>
                        <span className="rounded-full bg-amber-950 px-2 py-1 text-[10px] font-semibold capitalize text-amber-300">
                            {str(approval_request.get("risk", "high"))} risk
                        </span>
                    </div>

                    <div className="py-4 space-y-3 max-h-[45vh] overflow-y-auto">
                        <div>
                            <h3 className="text-[11px] font-semibold text-zinc-300">External effects</h3>
                            <ul className="mt-1.5 space-y-1.5">
                                {for effect_value in (approval_request.get("effects", []) as list) {
                                    effect: dict = effect_value as dict;
                                    <li key={str(effect.get("type", effect.get("description", "effect")))} className="text-xs leading-relaxed text-zinc-400">
                                        • {effect.get("description", effect.get("type", "Controls the target application"))}
                                    </li>
                                }}
                            </ul>
                        </div>
                        <div>
                            <h3 className="text-[11px] font-semibold text-zinc-300">Required permissions</h3>
                            <p className="mt-1 text-xs text-zinc-400">
                                {", ".join([str(value) for value in (approval_request.get("permissions", []) as list)]) or "macOS Automation and Accessibility"}
                            </p>
                        </div>
                        {if approval_request.get("program") {
                            <details className="rounded-xl bg-zinc-900 border border-zinc-800 px-3 py-2.5">
                                <summary className="cursor-pointer text-xs font-medium text-zinc-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400">
                                    Review validated automation steps
                                </summary>
                                <pre className="mt-2 overflow-x-auto whitespace-pre-wrap text-[10px] leading-relaxed text-zinc-400 font-mono select-text">{
                                    JSON.stringify(approval_request["program"], None, 2)  # jac:ignore[W2001,W6002]
                                }</pre>
                            </details>
                        }}
                    </div>

                    <div className="pt-4 border-t border-zinc-800 flex items-center justify-end gap-2">
                        <button
                            type="button"
                            autoFocus={True}
                            disabled={is_resolving_approval}
                            onClick={lambda { handle_resolve_approval(False); }}
                            className="rounded-xl bg-zinc-800 hover:bg-zinc-700 px-4 py-2.5 text-xs font-semibold text-zinc-200 disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            disabled={is_resolving_approval}
                            onClick={lambda { handle_resolve_approval(True); }}
                            className="rounded-xl bg-cyan-600 hover:bg-cyan-500 px-4 py-2.5 text-xs font-semibold text-white disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
                        >
                            {"Resolving…" if is_resolving_approval else "Run once"}
                        </button>
                    </div>
                </section>
            </div>
        }}
    </div>;
}
