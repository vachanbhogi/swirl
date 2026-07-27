"""Client workflow catalog, normalization, and naming helpers."""

glob SOURCE_ID: str = "workflow-source";
glob MAX_WORKFLOW_NAME_LENGTH: int = 80;
glob GENERATED_WORKFLOW_PREFIX: str = "AI - ";

glob:pub BLOCK_CATEGORIES: list[dict] = [
    {
        "id": "source",
        "name": "Workflow Source",
        "color": "#F97316",
        "bg": "rgba(249, 115, 22, 0.15)",
        "border": "#FB923C",
        "icon": "Radio",
    },
    {
        "id": "ai",
        "name": "AI & LLM Transforms",
        "color": "#F59E0B",
        "bg": "rgba(245, 158, 11, 0.15)",
        "border": "#FBBF24",
        "icon": "Sparkles",
    },
    {
        "id": "mac",
        "name": "macOS Automation",
        "color": "#06B6D4",
        "bg": "rgba(6, 182, 212, 0.15)",
        "border": "#67E8F9",
        "icon": "Command",
    },
    {
        "id": "mcp",
        "name": "MCP Tools",
        "color": "#10B981",
        "bg": "rgba(16, 185, 129, 0.15)",
        "border": "#34D399",
        "icon": "Plug",
    },
    {
        "id": "output",
        "name": "Outputs & Alerts",
        "color": "#F43F5E",
        "bg": "rgba(244, 63, 94, 0.15)",
        "border": "#FB7185",
        "icon": "Send",
    },
];

glob:pub BLOCK_LIBRARY: list[dict] = [
    {
        "type": "llm_summarize",
        "category": "ai",
        "title": "LLM Summarizer",
        "subtitle": "Jac `by llm()` Walker",
        "description": "Summarize text and extract key points using Jac LLM capabilities",
        "jacNode": "LLMTransformBlock",
        "inputs": ["text"],
        "outputs": ["summary", "actionItems"],
        "config": {
            "prompt": "Summarize concisely and extract 3 bullet action items.",
            "maxTokens": 500,
            "temperature": 0.2,
        },
    },
    {
        "type": "mac_wait_email",
        "category": "mac",
        "title": "Wait for Email",
        "subtitle": "Apple Mail Message Wait",
        "description": "Wait for a new Apple Mail message after the workflow starts",
        "jacNode": "MacAppBlock",
        "inputs": [],
        "outputs": ["text", "sender", "subject"],
        "config": {
            "app": "Mail",
            "action": "wait_for_new_message",
            "mailbox": "Inbox",
            "filterSubject": "",
            "checkIntervalSec": 15,
            "waitTimeoutSec": 0,
        },
    },
    {
        "type": "mac_notes",
        "category": "mac",
        "title": "Apple Notes",
        "subtitle": "macOS AppleScript Bridge",
        "description": "Create a new note or append text to an existing Apple Note",
        "jacNode": "MacAppBlock",
        "inputs": ["text", "title"],
        "outputs": ["noteId", "status"],
        "config": {
            "app": "Notes",
            "action": "create_note",
            "folder": "Swirl Automations",
            "defaultTitle": "Swirl Workflow Summary",
        },
    },
    {
        "type": "mac_finder",
        "category": "mac",
        "title": "Finder File Manager",
        "subtitle": "macOS File Operations",
        "description": "Organize files, create folders, move, or rename items",
        "jacNode": "MacAppBlock",
        "inputs": ["filePath"],
        "outputs": ["movedPath", "status"],
        "config": {
            "app": "Finder",
            "action": "organize_by_extension",
            "targetDirectory": "~/Desktop",
        },
    },
    {
        "type": "mac_notification",
        "category": "mac",
        "title": "Mac Notification",
        "subtitle": "System Notification Center",
        "description": "Post a native macOS banner notification alert",
        "jacNode": "MacAppBlock",
        "inputs": ["text", "title"],
        "outputs": ["status"],
        "config": {
            "app": "System",
            "action": "display_notification",
            "sound": "Glass",
        },
    },
    {
        "type": "mac_terminal",
        "category": "mac",
        "title": "Terminal Command",
        "subtitle": "Shell Script Walker",
        "description": "Run a zsh shell script or macOS CLI command",
        "jacNode": "MacAppBlock",
        "inputs": ["commandInput"],
        "outputs": ["stdout", "exitCode"],
        "config": {
            "app": "Terminal",
            "action": "exec_shell",
            "command": "echo \"Swirl execution completed at $(date)\"",
        },
    },
    {
        "type": "mcp_fetch",
        "category": "mcp",
        "title": "MCP Web Scraper",
        "subtitle": "Model Context Protocol",
        "description": "Fetch web page content through an HTTP MCP server",
        "jacNode": "MCPToolBlock",
        "inputs": ["url"],
        "outputs": ["markdownContent", "httpStatus"],
        "config": {
            "server": "fetch-mcp-server",
            "tool_name": "fetch",
            "url": "https://example.com",
            "timeoutMs": 10000,
        },
    },
    {
        "type": "mcp_fs",
        "category": "mcp",
        "title": "MCP Filesystem",
        "subtitle": "Local MCP Tool Adapter",
        "description": "Safely read and write files through the local MCP server",
        "jacNode": "MCPToolBlock",
        "inputs": ["path", "content"],
        "outputs": ["fileData", "status"],
        "config": {
            "server": "filesystem",
            "tool_name": "read_text_file",
            "path": "$SWIRL_DOCUMENTS",
            "allowedDir": "$SWIRL_DOCUMENTS",
        },
    },
    {
        "type": "mcp_search",
        "category": "mcp",
        "title": "MCP Web Search",
        "subtitle": "Brave Search MCP",
        "description": "Perform real-time web queries through the configured MCP server",
        "jacNode": "MCPToolBlock",
        "inputs": ["query"],
        "outputs": ["searchResults", "sources"],
        "config": {
            "server": "brave-search-mcp",
            "tool_name": "brave_web_search",
            "query": "",
            "maxResults": 5,
        },
    },
    {
        "type": "output_slack",
        "category": "output",
        "title": "Slack Webhook",
        "subtitle": "Slack Channel Alert",
        "description": "Post a formatted message to a Slack incoming webhook",
        "jacNode": "OutputBlock",
        "inputs": ["text"],
        "outputs": ["response"],
        "config": {
            "webhookUrl": "https://hooks.slack.com/services/MOCK/SWIRL/KEY",
            "channel": "#automations",
        },
    },
];

glob:pub SOURCE_EVENTS: dict[str, dict] = {
    "trigger_email": {
        "type": "trigger_email",
        "title": "On Email Received",
        "description": "Start when any new message arrives in Apple Mail.",
        "config": {
            "mailbox": "Inbox",
            "filterSubject": "",
            "checkIntervalSec": 15,
            "waitTimeoutSec": 0,
        },
    },
    "trigger_cron": {
        "type": "trigger_cron",
        "title": "Repeat Schedule",
        "description": "Start on a recurring cron schedule.",
        "config": {
            "cron": "*/15 * * * *",
            "timezone": "America/Los_Angeles",
        },
    },
    "trigger_voice": {
        "type": "trigger_voice",
        "title": "Voice Command",
        "description": "Start when a voice command or wake word is spoken.",
        "config": {
            "wakeWord": "Hey Swirl",
            "language": "en-US",
            "listenTimeoutSec": 30,
        },
    },
    "trigger_sms": {
        "type": "trigger_sms",
        "title": "Text Myself",
        "description": "Start when a Messages text involves the configured phone number.",
        "config": {
            "phoneNumber": "8604644276",
            "checkIntervalSec": 1,
        },
    },
    "trigger_webhook": {
        "type": "trigger_webhook",
        "title": "HTTP Webhook",
        "description": "Start when an HTTP payload is posted to a local endpoint.",
        "config": {
            "host": "127.0.0.1",
            "port": 8787,
            "path": "/api/v1/webhook",
            "method": "POST",
            "authRequired": False,
            "authToken": "",
        },
    },
    "trigger_clipboard": {
        "type": "trigger_clipboard",
        "title": "Clipboard Listener",
        "description": "Start when text is copied to the macOS clipboard.",
        "config": {
            "watchText": True,
            "minChars": 1,
            "checkIntervalSec": 1,
        },
    },
    "trigger_file": {
        "type": "trigger_file",
        "title": "On File Created",
        "description": "Start when a file appears in the watched Finder folder.",
        "config": {
            "watchPath": "~/Downloads",
            "filePattern": "*",
            "checkIntervalSec": 2,
        },
    },
};

glob:pub INITIAL_NODES: list[dict] = [
    {
        "id": "workflow-on-run",
        "type": "on_run",
        "title": "On Run",
        "category": "source",
        "jacNode": "SourceBlock",
        "x": 60,
        "y": 120,
        "config": {
            "eventType": "trigger_email",
            "runMode": "once",
            "mailbox": "Inbox",
            "filterSubject": "",
            "checkIntervalSec": 15,
            "waitTimeoutSec": 0,
        },
        "status": "idle",
    },
];
glob:pub INITIAL_EDGES: list[dict] = [];


def clone_json(value: any) -> any {
    if isinstance(value, dict) {
        copied: dict = {};
        for key in value {
            copied[str(key)] = clone_json(value[key]);
        }
        return copied;
    }
    if isinstance(value, list) {
        return [clone_json(item) for item in value];
    }
    return value;
}


def source_config(event_type: str = "trigger_email", config: dict = {}) -> dict {
    normalized: str = event_type if event_type in SOURCE_EVENTS else "trigger_email";
    defaults: dict = clone_json(SOURCE_EVENTS[normalized]["config"]) as dict;
    return {
        "eventType": normalized,
        "runMode": "once",
        **defaults,
        **config,
    };
}


def:pub change_source_event(event_type: str, current: dict = {}) -> dict {
    run_mode: str = (
        "continuous" if current.get("runMode") == "continuous" else "once"
    );
    return source_config(
        event_type,
        {"eventType": event_type, "runMode": run_mode},
    );
}


def normalize_node_position(
    workflow_node: dict,
    default_x: float = 250.0,
    default_y: float = 180.0,
) -> dict {
    position: dict = (
        workflow_node.get("position") as dict
        if isinstance(workflow_node.get("position"), dict)
        else {}
    );
    raw_x: any = (
        workflow_node.get("x")
        if isinstance(workflow_node.get("x"), int)
            or isinstance(workflow_node.get("x"), float)
        else position.get("x")
    );
    raw_y: any = (
        workflow_node.get("y")
        if isinstance(workflow_node.get("y"), int)
            or isinstance(workflow_node.get("y"), float)
        else position.get("y")
    );
    x: float = float(raw_x) if raw_x is not None else default_x;
    y: float = float(raw_y) if raw_y is not None else default_y;
    return {
        **workflow_node,
        "x": x,
        "y": y,
        "position": {"x": x, "y": y},
    };
}


def create_source_node(
    config: dict = {},
    x: float = 32.0,
    y: float = 140.0,
) -> dict {
    event_type: str = str(config.get("eventType") or "trigger_email");
    return {
        "id": SOURCE_ID,
        "type": "source",
        "title": "Source",
        "category": "source",
        "jacNode": "SourceBlock",
        "x": x,
        "y": y,
        "position": {"x": x, "y": y},
        "config": source_config(event_type, config),
        "status": "idle",
    };
}


def legacy_trigger_to_source(trigger: dict) -> dict {
    event_type: str = (
        str(trigger.get("type"))
        if trigger.get("type") in SOURCE_EVENTS
        else "trigger_email"
    );
    positioned: dict = normalize_node_position(trigger, 32.0, 140.0);
    trigger_config: dict = (
        trigger.get("config") as dict
        if isinstance(trigger.get("config"), dict)
        else {}
    );
    return create_source_node(
        {"eventType": event_type, **trigger_config},
        float(positioned["x"]),
        float(positioned["y"]),
    );
}


"""Return one canonical Source plus valid, positioned downstream nodes."""
def:pub normalize_workflow(nodes: list = [], edges: list = []) -> dict {
    input_nodes: list[dict] = clone_json(nodes or []) as list[dict];
    input_edges: list[dict] = clone_json(edges or []) as list[dict];
    source_candidates: list[dict] = [
        node
        for node in input_nodes
        if node.get("category") == "source" or node.get("type") == "source"
    ];
    legacy_triggers: list[dict] = [
        node for node in input_nodes if node.get("category") == "trigger"
    ];
    source_seed: dict = (
        source_candidates[0]
        if source_candidates
        else (
            legacy_trigger_to_source(legacy_triggers[0])
            if legacy_triggers
            else create_source_node()
        )
    );
    source: dict = normalize_node_position(source_seed, 32.0, 140.0);
    existing_source_id: str = (
        str(source_candidates[0].get("id") or "") if source_candidates else ""
    );
    removed_ids: set[str] = set();
    for duplicate in source_candidates[1:] {
        removed_ids.add(str(duplicate.get("id") or ""));
    }
    for trigger in legacy_triggers {
        trigger_id: str = str(trigger.get("id") or "");
        if trigger_id != str(source.get("id") or "") {
            removed_ids.add(trigger_id);
        }
    }
    if existing_source_id and existing_source_id != SOURCE_ID {
        removed_ids.add(existing_source_id);
    }

    source_event: str = (
        str((source.get("config") as dict).get("eventType"))
        if isinstance(source.get("config"), dict)
            and (source.get("config") as dict).get("eventType")
        else "trigger_email"
    );
    source = {
        **source,
        "id": SOURCE_ID,
        "type": "source",
        "category": "source",
        "title": "Source",
        "jacNode": "SourceBlock",
        "config": source_config(
            source_event,
            source.get("config") as dict
            if isinstance(source.get("config"), dict)
            else {},
        ),
    };

    retained_nodes: list[dict] = [];
    for node in input_nodes {
        node_id: str = str(node.get("id") or "");
        if node_id not in removed_ids and node.get("category") != "trigger" {
            retained_nodes.append(
                normalize_node_position(
                    {**node, "status": node.get("status") or "idle"}
                )
            );
        }
    }
    node_ids: set[str] = {SOURCE_ID};
    for node in retained_nodes {
        node_ids.add(str(node.get("id") or ""));
    }

    rewired_edges: list[dict] = [];
    for edge in input_edges {
        edge_source: str = (
            SOURCE_ID
            if existing_source_id and edge.get("source") == existing_source_id
            else str(edge.get("source") or "")
        );
        edge_target: str = (
            SOURCE_ID
            if existing_source_id and edge.get("target") == existing_source_id
            else str(edge.get("target") or "")
        );
        if (
            edge_target != SOURCE_ID
            and edge_source not in removed_ids
            and edge_target not in removed_ids
            and edge_source in node_ids
            and edge_target in node_ids
        ) {
            rewired_edges.append(
                {**edge, "source": edge_source, "target": edge_target}
            );
        }
    }

    old_trigger_ids: set[str] = {
        str(trigger.get("id") or "") for trigger in legacy_triggers
    };
    for edge in input_edges {
        target_id: str = str(edge.get("target") or "");
        if (
            str(edge.get("source") or "") not in old_trigger_ids
            or target_id not in node_ids
        ) {
            continue;
        }
        duplicate: bool = `any(
            candidate["source"] == SOURCE_ID and candidate["target"] == target_id
            for candidate in rewired_edges
        );
        if not duplicate {
            rewired_edges.append(
                {
                    "id": f"edge-{SOURCE_ID}-{target_id}",
                    "source": SOURCE_ID,
                    "target": target_id,
                    "sourcePort": "event",
                    "targetPort": edge.get("targetPort") or "in",
                }
            );
        }
    }

    incoming_targets: set[str] = {
        str(edge.get("target") or "") for edge in rewired_edges
    };
    for node in retained_nodes {
        node_id: str = str(node.get("id") or "");
        has_source_edge: bool = `any(
            edge.get("source") == SOURCE_ID and edge.get("target") == node_id
            for edge in rewired_edges
        );
        if (
            node_id != SOURCE_ID
            and node_id not in incoming_targets
            and not has_source_edge
        ) {
            rewired_edges.append(
                {
                    "id": f"edge-{SOURCE_ID}-{node_id}",
                    "source": SOURCE_ID,
                    "target": node_id,
                    "sourcePort": "event",
                    "targetPort": "in",
                }
            );
        }
    }
    return {
        "nodes": [source]
        + [node for node in retained_nodes if node.get("id") != SOURCE_ID],
        "edges": rewired_edges,
    };
}


def:pub suggest_generated_workflow_name(prompt: str) -> str {
    allowed: str = (
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        + "abcdefghijklmnopqrstuvwxyz"
        + "0123456789 _-"
    );
    cleaned: str = "".join([
        character if character in allowed else " "
        for character in prompt
    ]);
    cleaned = " ".join(cleaned.split());
    title: str = cleaned or "Generated Workflow";
    return (GENERATED_WORKFLOW_PREFIX + title)[:MAX_WORKFLOW_NAME_LENGTH].rstrip();
}
