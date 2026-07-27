import os;
import from backend.workflow_agent {
    compile_llm_workflow, prompt_to_workflow_rules, plan_workflow,
    workflow_draft_to_ast,
    WorkflowDraft, WorkflowNodeDraft, WorkflowEdgeDraft
}
import from backend.mac_control {
    classify_mac_action, validate_mac_action
}
import from backend.mcp_bridge {
    initialize_request, tool_call_request, validate_transport,
    builtin_mcp_servers, builtin_mcp_server
}
import from backend.code_generator { generate_jac_source }


test "prompt compiler creates connected desktop workflow" {
    ast = prompt_to_workflow_rules(
        "Organize my Desktop and create an Apple Note"
    );
    assert len(ast.nodes) == 3;
    assert len(ast.edges) == 2;
    assert ast.nodes[0]["category"] == "source";
    assert ast.nodes[1]["category"] == "mac";
}


test "prompt compiler creates continuous self-text source" {
    ast = prompt_to_workflow_rules(
        "When I text myself, run the workflow from what I say"
    );
    assert ast.nodes[0]["category"] == "source";
    assert ast.nodes[0]["config"]["eventType"] == "trigger_sms";
    assert ast.nodes[0]["config"]["runMode"] == "continuous";
    assert ast.nodes[0]["config"]["phoneNumber"] == "8604644276";
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
