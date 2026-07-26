import from backend.workflow_agent {
    prompt_to_workflow_rules, plan_workflow
}
import from backend.mac_control {
    classify_mac_action, validate_mac_action,
    applescript_escape, html_escape, string_param, expand_home,
    build_create_note_script, build_notification_script,
    build_applescript, validate_restricted_applescript,
    MacActionResult
}
import from backend.mcp_bridge {
    initialize_request, tool_call_request, validate_transport,
    MCPResponse, MCPToolSchema, MCPServerConfig,
    validate_server_name, parse_tools_response,
    validate_tool_arguments, notifications_initialized_request,
    resources_list_request, prompts_list_request
}
import from backend.code_generator { generate_jac_source }
import from backend.models {
    WorkflowDocument, ExecutionEvent, ExecutionSummary
}
import from backend.storage { safe_name }
import from backend.block_definitions {
    BLOCK_CATEGORIES, BLOCK_LIBRARY, workflow_presets,
    default_starter_workflow, get_block_by_type,
    get_blocks_by_category, category_color
}


# ============================================================
# Workflow Agent Tests
# ============================================================

test "prompt compiler creates connected desktop workflow" {
    ast = prompt_to_workflow_rules("Organize my Desktop and create an Apple Note");
    assert len(ast.nodes) == 3;
    assert len(ast.edges) == 2;
    assert ast.nodes[1]["category"] == "mac";
}


test "workflow planner follows graph topology" {
    workflow = {
        "nodes": [
            {"id": "b", "type": "mac_notification", "title": "Notify", "category": "mac", "config": {}},
            {"id": "a", "type": "trigger_file", "title": "Trigger", "category": "trigger", "config": {}},
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
            {"id": "a", "type": "trigger", "title": "A", "category": "trigger", "config": {}},
            {"id": "b", "type": "output", "title": "B", "category": "output", "config": {}},
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


test "prompt compiler handles email keyword" {
    ast = prompt_to_workflow_rules("Check my email and summarize");
    assert len(ast.nodes) >= 3;
    assert ast.nodes[0]["category"] == "trigger";
    assert ast.source == "rules";
}


test "prompt compiler handles calendar keyword" {
    ast = prompt_to_workflow_rules("Create a meeting event on my calendar");
    assert len(ast.nodes) == 3;
    assert ast.nodes[2]["category"] == "mac";
}


test "prompt compiler fallback to MCP workflow" {
    ast = prompt_to_workflow_rules("Do something generic");
    assert len(ast.nodes) == 3;
    assert any([n["category"] == "mcp" for n in ast.nodes]);
}


# ============================================================
# macOS Policy & AppleScript Tests
# ============================================================

test "mac policy gates destructive actions" {
    policy = classify_mac_action("Finder", "organize_by_extension");
    assert policy.requires_approval;
    assert policy.risk == "high";
    assert validate_mac_action("Notes", "create_note");
    assert not validate_mac_action("Finder", "delete");
}


test "mac policy classifies medium risk actions" {
    policy = classify_mac_action("Calendar", "create_event");
    assert policy.risk == "medium";
    assert policy.requires_approval;
}


test "mac policy classifies low risk actions" {
    policy = classify_mac_action("Notes", "create_note");
    assert policy.risk == "low";
    assert not policy.requires_approval;
}


test "applescript_escape handles special characters" {
    assert '"' not in applescript_escape('Say "hello"');
    result = applescript_escape("line1\nline2");
    assert "\\n" in result;
}


test "html_escape handles HTML entities" {
    result = html_escape('<script>alert("xss")</script>');
    assert "<" not in result;
    assert "&lt;" in result;
}


test "string_param extracts values safely" {
    params = {"name": "Alice", "count": 42};
    assert string_param(params, "name", "default") == "Alice";
    assert string_param(params, "missing", "fallback") == "fallback";
}


test "build_create_note_script produces valid AppleScript" {
    script = build_create_note_script("Test Note", "Hello world", "Swirl");
    assert "Notes" in script;
    assert "Test Note" in script or "Swirl" in script;
}


test "build_notification_script produces valid AppleScript" {
    script = build_notification_script("Task done", "Swirl Agent", "Glass");
    assert "display notification" in script;
    assert "Glass" in script;
}


test "build_applescript dispatcher routes correctly" {
    script = build_applescript("System", "display_notification", {
        "text": "Hello", "title": "Swirl", "sound": "Glass"
    });
    assert "display notification" in script;
}


test "validate_restricted_applescript blocks shell escapes" {
    assert not validate_restricted_applescript(
        'tell application "Notes" to do shell script "whoami"'
    );
    assert not validate_restricted_applescript(
        'tell application "Terminal" to activate'
    );
}


test "MacActionResult factory methods work correctly" {
    success = MacActionResult(success=True, output={"key": "val"}, risk="low");
    assert success.success;
    assert success.to_dict()["risk"] == "low";

    failure = MacActionResult(success=False, error="something broke", risk="high");
    assert not failure.success;
    assert failure.error == "something broke";
}


# ============================================================
# MCP Bridge Tests
# ============================================================

test "mcp bridge produces protocol requests" {
    init = initialize_request("1.0.0");
    call = tool_call_request("read_file", {"path": "/tmp/example"});
    assert init.method == "initialize";
    assert call.params["name"] == "read_file";
    assert validate_transport({"transport": "stdio", "command": "npx"});
    assert not validate_transport({"transport": "http", "url": "http://example.com"});
}


test "MCPResponse detects errors" {
    ok_resp = MCPResponse(id=1, result={"tools": []});
    assert not ok_resp.is_error();

    err_resp = MCPResponse(id=1, error={"code": -32600, "message": "Invalid"});
    assert err_resp.is_error();
    assert "Invalid" in err_resp.error_message();
}


test "MCPToolSchema converts to block definition" {
    schema = MCPToolSchema(
        name="read_file",
        description="Read a file from disk",
        input_schema={"type": "object", "properties": {"path": {"type": "string"}}},
    );
    block = schema.to_block_definition();
    assert block["type"] == "mcp_read_file";
    assert block["category"] == "mcp";
    assert block["jacNode"] == "MCPToolBlock";
}


test "MCPServerConfig validates correctly" {
    stdio_config = MCPServerConfig(
        name="test-server",
        transport="stdio",
        command="npx",
        args=["-y", "@mcp/server"],
    );
    assert stdio_config.validate();

    bad_config = MCPServerConfig(name="test", transport="stdio", command="");
    assert not bad_config.validate();

    http_config = MCPServerConfig(
        name="remote",
        transport="http",
        url="https://api.example.com/mcp",
    );
    assert http_config.validate();
}


test "validate_server_name enforces naming rules" {
    assert validate_server_name("my-server");
    assert validate_server_name("server_123");
    assert not validate_server_name("");
    assert not validate_server_name("a" * 81);
}


test "parse_tools_response extracts tools" {
    response = {
        "tools": [
            {"name": "fetch_url", "description": "Fetch a URL", "inputSchema": {}},
            {"name": "read_file", "description": "Read a file"},
        ]
    };
    tools = parse_tools_response(response);
    assert len(tools) == 2;
    assert tools[0].name == "fetch_url";
}


test "notifications_initialized_request is valid" {
    req = notifications_initialized_request();
    assert req.method == "notifications/initialized";
}


test "resources_list_request is valid" {
    req = resources_list_request();
    assert req.method == "resources/list";
}


test "prompts_list_request is valid" {
    req = prompts_list_request();
    assert req.method == "prompts/list";
}


# ============================================================
# Code Generator Tests
# ============================================================

test "code generator emits graph-native Jac" {
    workflow = {
        "nodes": [
            {"id": "start", "type": "trigger", "title": "Start", "category": "trigger", "config": {}},
            {"id": "done", "type": "output", "title": "Done", "category": "output", "config": {}},
        ],
        "edges": [{"id": "start-done", "source": "start", "target": "done"}],
    };
    source = generate_jac_source(workflow);
    assert "root spawn WorkflowExecutorWalker()" in source;
    assert "node_start ++> node_done" in source;
}


# ============================================================
# Models Tests
# ============================================================

test "WorkflowDocument validates a valid DAG" {
    doc = WorkflowDocument(
        nodes=[
            {"id": "a", "title": "A"},
            {"id": "b", "title": "B"},
        ],
        edges=[{"id": "e1", "source": "a", "target": "b"}],
    );
    doc.validate();
    assert True;
}


test "WorkflowDocument rejects empty workflow" {
    doc = WorkflowDocument(nodes=[], edges=[]);
    try {
        doc.validate();
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}


test "WorkflowDocument rejects cycles" {
    doc = WorkflowDocument(
        nodes=[{"id": "a", "title": "A"}, {"id": "b", "title": "B"}],
        edges=[
            {"id": "e1", "source": "a", "target": "b"},
            {"id": "e2", "source": "b", "target": "a"},
        ],
    );
    try {
        doc.validate();
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}


test "ExecutionEvent serializes correctly" {
    event = ExecutionEvent(
        event="node_start",
        node_id="node-1",
        title="Trigger",
        status="running",
    );
    d = event.to_dict();
    assert d["event"] == "node_start";
    assert d["nodeId"] == "node-1";
}


test "ExecutionSummary serializes correctly" {
    summary = ExecutionSummary(
        success=True,
        context={"key": "val"},
        results={"node-1": {"output": "done"}},
        completed_node_ids=["node-1"],
    );
    d = summary.to_dict();
    assert d["success"];
    assert len(d["completedNodeIds"]) == 1;
}


# ============================================================
# Storage Tests
# ============================================================

test "safe_name rejects empty names" {
    try {
        safe_name("");
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}


test "safe_name rejects special characters" {
    try {
        safe_name("my@workflow!");
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}


test "safe_name replaces spaces with underscores" {
    result = safe_name("My Workflow Name");
    assert result == "My_Workflow_Name";
}


test "safe_name rejects names over 80 chars" {
    try {
        safe_name("a" * 81);
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}


# ============================================================
# Block Definitions Tests
# ============================================================

test "BLOCK_CATEGORIES returns 6 categories" {
    cats = BLOCK_CATEGORIES();
    assert len(cats) == 6;
    ids = [c.id for c in cats];
    assert "trigger" in ids;
    assert "ai" in ids;
    assert "mac" in ids;
    assert "mcp" in ids;
    assert "logic" in ids;
    assert "output" in ids;
}


test "BLOCK_LIBRARY returns all block definitions" {
    blocks = BLOCK_LIBRARY();
    assert len(blocks) >= 14;
    types = [b.block_type for b in blocks];
    assert "trigger_email" in types;
    assert "llm_summarize" in types;
    assert "mac_notes" in types;
    assert "mcp_fetch" in types;
}


test "get_block_by_type finds existing blocks" {
    block = get_block_by_type("trigger_email");
    assert block is not None;
    assert block.title == "On Email Received";
}


test "get_block_by_type returns None for unknown type" {
    block = get_block_by_type("nonexistent_block");
    assert block is None;
}


test "get_blocks_by_category filters correctly" {
    triggers = get_blocks_by_category("trigger");
    assert len(triggers) == 3;
    for block in triggers {
        assert block.category == "trigger";
    }
}


test "category_color returns correct colors" {
    assert category_color("trigger") == "#8B5CF6";
    assert category_color("ai") == "#F59E0B";
    assert category_color("nonexistent") == "#888888";
}


test "default_starter_workflow has nodes and edges" {
    wf = default_starter_workflow();
    assert "nodes" in wf;
    assert "edges" in wf;
    assert len(wf["nodes"]) == 4;
    assert len(wf["edges"]) == 3;
}


test "workflow_presets returns 3 presets" {
    presets = workflow_presets();
    assert len(presets) == 3;
    ids = [p.id for p in presets];
    assert "email_notes" in ids;
    assert "desktop_cleaner" in ids;
    assert "mcp_scraper" in ids;
}

