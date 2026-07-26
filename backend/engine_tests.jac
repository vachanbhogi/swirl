import from backend.workflow_agent {
    prompt_to_workflow_rules, plan_workflow
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
                "config": {"eventType": "trigger_file"},
            },
        ],
        "edges": [{"id": "a-b", "source": "a", "target": "b"}],
    };
    plan = plan_workflow(workflow);
    assert plan[0]["id"] == "a";
    assert plan[1]["id"] == "b";
}


test "workflow planner rejects cycles" {
    workflow = {
        "nodes": [
            {
                "id": "a",
                "type": "source",
                "title": "Source",
                "category": "source",
                "config": {"eventType": "trigger_email"},
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
                "config": {"eventType": "trigger_email"},
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
