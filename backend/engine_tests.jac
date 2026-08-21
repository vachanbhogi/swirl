import os;
import from backend.workflow_agent {
    compile_llm_workflow, prompt_to_workflow_rules, plan_workflow,
    workflow_draft_to_ast,
    PromptToWorkflowWalker, WorkflowDraft, WorkflowNodeDraft,
    WorkflowEdgeDraft, GeneratedAppToolDraft, GeneratedToolInput,
    GeneratedToolStep, GeneratedToolEffect, validate_app_tool_draft,
    is_app_tool_prompt
}
import from backend.mac_control {
    classify_mac_action, validate_mac_action
}
import from backend.mcp_bridge {
    initialize_request, tool_call_request, validate_transport,
    builtin_mcp_servers, builtin_mcp_server
}
import from backend.code_generator { generate_jac_source }
import from backend.models { validate_workflow }
import from backend.storage { workflow_with_positions }


test "prompt compiler creates connected desktop workflow" {
    ast = prompt_to_workflow_rules(
        "Organize my Desktop and create an Apple Note"
    );
    assert len(ast.nodes) == 3;
    assert len(ast.edges) == 2;
    assert ast.nodes[0]["category"] == "source";
    assert ast.nodes[1]["category"] == "mac";
}


test "prompt walker exposes the generated workflow directly" {
    result = root spawn PromptToWorkflowWalker(
        user_prompt="When a new email arrives, summarize it"
    );
    assert result.generated is not None;
    assert result.generated.nodes[0]["config"]["eventType"] == "trigger_email";
}


test "App Agents are valid workflow actions" {
    workflow = {
        "nodes": [
            {
                "id": "workflow-source",
                "type": "source",
                "title": "Source",
                "category": "source",
                "config": {"eventType": "trigger_email", "runMode": "once"},
            },
            {
                "id": "app-agent",
                "type": "mac_app_agent",
                "title": "Discord Agent",
                "category": "mac",
                "config": {
                    "application": "Discord",
                    "prompt": "Open my DM with Alex and send: Running late.",
                },
            },
        ],
        "edges": [{
            "id": "source-agent",
            "source": "workflow-source",
            "target": "app-agent",
        }],
    };
    validated = validate_workflow(workflow);
    assert validated["valid"];
    assert plan_workflow(workflow)[1]["type"] == "mac_app_agent";
}


test "generated application tool drafts use safe typed operations" {
    draft = GeneratedAppToolDraft(
        name="Send Discord DM",
        description="Send a direct message to a selected Discord recipient.",
        application_query="Discord",
        inputs=[
            GeneratedToolInput(key="recipient", label="Recipient"),
            GeneratedToolInput(key="message", label="Message"),
        ],
        program=[
            GeneratedToolStep(op="activate_app"),
            GeneratedToolStep(op="wait_frontmost"),
            GeneratedToolStep(op="key_chord", keys=["command", "k"]),
            GeneratedToolStep(
                op="wait_element", role="AXTextField", timeout_sec=5.0
            ),
            GeneratedToolStep(op="type_input", input_key="recipient"),
            GeneratedToolStep(op="press_key", key="return"),
            GeneratedToolStep(op="type_input", input_key="message"),
            GeneratedToolStep(op="press_key", key="return"),
        ],
        effects=[GeneratedToolEffect(
            effect_type="send", description="Sends one Discord message",
            requires_approval=True
        )],
        permissions=["Automation", "Accessibility"],
        risk="medium",
    );
    validation = validate_app_tool_draft(draft);
    assert validation["valid"];
    assert draft.to_dict("Make a tool to text my friend on Discord")["program"][4]["inputKey"] == "recipient";
    assert is_app_tool_prompt("Make a tool to text my friend on Discord");
    assert not is_app_tool_prompt("Every morning summarize my inbox");
}


test "generated application tool workflow pins snapshot and position" {
    fingerprint: str = "a" * 64;
    workflow = {
        "nodes": [
            {
                "id": "workflow-source", "type": "source",
                "title": "On Run", "category": "source", "config": {}
            },
            {
                "id": "discord-tool", "type": "generated_app_tool",
                "title": "Send Discord DM", "category": "mac",
                "toolRef": {
                    "id": "tool-discord", "version": 1,
                    "fingerprint": fingerprint
                },
                "toolSnapshot": {
                    "target": {"bundleId": "com.hnc.Discord"},
                    "inputs": [
                        {"key": "recipient", "sensitive": True},
                        {"key": "message", "sensitive": True}
                    ],
                    "program": [
                        {"op": "activate_app"}, {"op": "wait_frontmost"}
                    ],
                    "effects": [{"type": "send", "requiresApproval": True}],
                },
                "config": {"bindings": {
                    "recipient": {
                        "kind": "literal", "value": "Private recipient"
                    },
                    "message": {"kind": "context", "path": "text"},
                }},
                "position": {"x": 260.0, "y": 200.0},
            },
        ],
        "edges": [{
            "id": "source-tool", "source": "workflow-source",
            "target": "discord-tool"
        }],
    };
    assert validate_workflow(workflow)["valid"];
    planned = plan_workflow(workflow);
    assert planned[1]["toolRef"]["version"] == 1;
    assert planned[1]["position"]["x"] == 260.0;
    source = generate_jac_source(workflow);
    assert "tool_ref=" in source;
    assert "tool_snapshot=" in source;
    assert "position=" in source;
    assert "Private recipient" not in source;
}


test "prompt compiler creates continuous self-text source" {
    ast = prompt_to_workflow_rules(
        "When I text myself, run the workflow from what I say"
    );
    assert ast.nodes[0]["category"] == "source";
    assert ast.nodes[0]["config"]["eventType"] == "trigger_sms";
    assert ast.nodes[0]["config"]["runMode"] == "continuous";
    assert ast.nodes[0]["config"]["phoneNumber"] == "8604644276";
    assert len(ast.nodes) == 4;
    assert len(ast.edges) == 3;
    assert ast.nodes[1]["type"] == "llm_summarize";
    assert ast.nodes[2]["type"] == "mac_notes";
    assert ast.nodes[2]["config"]["folder"] == "Swirl Action Items";
    assert ast.nodes[2]["config"]["noteStyle"] == "actionBrief";
    assert ast.nodes[3]["type"] == "mac_notification";
    assert ast.edges[0]["source"] == "workflow-source";
}


test "workflow planner follows graph topology" {
    workflow = {
        "nodes": [
            {
                "id": "b",
                "type": "mac_notification",
                "title": "Notify",
                "category": "mac",
                "config": {},
            },
            {
                "id": "a",
                "type": "source",
                "title": "Source",
                "category": "source",
                "config": {},
            },
        ],
        "edges": [{"id": "a-b", "source": "a", "target": "b"}],
    };
    plan = plan_workflow(workflow);
    assert plan[0]["id"] == "a";
    assert plan[1]["id"] == "b";
}


test "typed LLM draft becomes a canonical source workflow" {
    draft = WorkflowDraft(
        source_event_type="trigger_webhook",
        source_config_json="{\"port\": 9000, \"path\": \"/notes\"}",
        run_mode="continuous",
        nodes=[
            WorkflowNodeDraft(
                id="note", block_type="mac_notes", title="Save Note",
                config_json="{\"app\": \"Notes\", \"action\": \"create_note\"}"
            )
        ],
        edges=[
            WorkflowEdgeDraft(source="workflow-source", target="note")
        ],
    );
    ast = workflow_draft_to_ast(
        "Whenever a webhook arrives, save a note", draft
    );
    assert ast.source == "llm";
    assert ast.nodes[0]["id"] == "workflow-source";
    assert ast.nodes[0]["config"]["runMode"] == "continuous";
    assert ast.nodes[0]["config"]["port"] == 9000;
    assert ast.nodes[1]["type"] == "mac_notes";
}


test "typed LLM draft applies self-text source defaults" {
    draft = WorkflowDraft(
        source_event_type="trigger_sms",
        nodes=[
            WorkflowNodeDraft(
                id="notify", block_type="mac_notification",
                title="Notify"
            )
        ],
        edges=[
            WorkflowEdgeDraft(source="workflow-source", target="notify")
        ],
    );
    ast = workflow_draft_to_ast(
        "Whenever I text myself, notify me", draft
    );
    assert ast.nodes[0]["config"]["eventType"] == "trigger_sms";
    assert ast.nodes[0]["config"]["phoneNumber"] == "8604644276";
    assert ast.nodes[0]["config"]["checkIntervalSec"] == 1;
}


test "typed LLM draft rejects unsupported blocks" {
    draft = WorkflowDraft(
        source_event_type="trigger_email",
        nodes=[
            WorkflowNodeDraft(
                id="bad", block_type="made_up_tool", title="Bad"
            )
        ],
        edges=[
            WorkflowEdgeDraft(source="workflow-source", target="bad")
        ],
    );
    try {
        workflow_draft_to_ast("Do something unsupported", draft);
        assert False;
    } except ValueError as error {
        assert "Unsupported generated block type" in str(error);
    }
}


test "configured Jac LLM generates a live workflow when explicitly enabled" {
    if os.getenv("SWIRL_RUN_LLM_SMOKE", "") == "1" {
        ast = compile_llm_workflow(
            "Whenever a new email arrives, summarize it and create an Apple Note"
        );
        assert ast.source == "llm";
        assert ast.nodes[0]["category"] == "source";
        assert len(ast.edges) > 0;
    }
}


test "workflow planner rejects cycles" {
    workflow = {
        "nodes": [
            {
                "id": "a",
                "type": "source",
                "title": "Source",
                "category": "source",
                "config": {},
            },
            {
                "id": "b",
                "type": "output",
                "title": "Done",
                "category": "output",
                "config": {},
            },
        ],
        "edges": [
            {"id": "a-b", "source": "a", "target": "b"},
            {"id": "b-a", "source": "b", "target": "a"},
        ],
    };
    try {
        plan_workflow(workflow);
        assert False, "cycle should have raised";
    } except ValueError {
        assert True;
    }
}


test "mac policy gates destructive actions" {
    policy = classify_mac_action("Finder", "organize_by_extension");
    assert policy.requires_approval;
    assert policy.risk == "high";
    assert validate_mac_action("Notes", "create_note");
    assert validate_mac_action("Mail", "wait_for_new_message");
    assert not validate_mac_action("Finder", "delete");
}


test "mcp bridge produces protocol requests" {
    init = initialize_request("1.0.0");
    call = tool_call_request("read_text_file", {"path": "/tmp/example"});
    assert init.method == "initialize";
    assert call.params["name"] == "read_text_file";
    assert validate_transport({"transport": "stdio", "command": "npx"});
    assert not validate_transport({
        "transport": "http",
        "url": "http://example.com",
    });
}


test "jac owns valid built-in MCP server definitions" {
    servers = builtin_mcp_servers();
    assert len(servers) == 3;
    for server in servers {
        assert validate_transport(server);
    }
    fetch = builtin_mcp_server("fetch-mcp-server");
    assert fetch["command"] == "uvx";
    filesystem = builtin_mcp_server("filesystem");
    assert filesystem["command"] == "npx";
}


test "code generator emits SourceBlock graph" {
    workflow = {
        "nodes": [
            {
                "id": "start",
                "type": "source",
                "title": "Source",
                "category": "source",
                "config": {},
            },
            {
                "id": "done",
                "type": "output",
                "title": "Done",
                "category": "output",
                "config": {},
            },
        ],
        "edges": [
            {"id": "start-done", "source": "start", "target": "done"}
        ],
    };
    source = generate_jac_source(workflow);
    assert "SourceBlock" in source;
    assert "node_start ++> node_done" in source;
}
