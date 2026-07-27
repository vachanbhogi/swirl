"""Swirl's graph-native workflow model and agent walkers."""

import json;
import from datetime { datetime, timezone }


obj BlockView {
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has config: dict = {};
    has custom_prompt: str = "";
    has status: str = "idle";
    has output: dict = {};

    def to_dict() -> dict {
        return {
            "id": self.id,
            "type": self.block_type,
            "title": self.title,
            "category": self.category,
            "config": self.config,
            "customPrompt": self.custom_prompt,
            "status": self.status,
            "output": self.output,
        };
    }
}


obj WorkflowAst {
    has nodes: list[dict] = [];
    has edges: list[dict] = [];
    has source: str = "rules";
    has warnings: list[str] = [];

    def to_dict() -> dict {
        return {
            "nodes": self.nodes,
            "edges": self.edges,
            "source": self.source,
            "warnings": self.warnings,
        };
    }
}

"""Typed LLM output. Dynamic block configuration is encoded as JSON text so
Jac can derive a strict byLLM schema without using an untyped dict."""
obj WorkflowNodeDraft {
    has id: str;
    has block_type: str;
    has title: str;
    has config_json: str = "{}";
}


obj WorkflowEdgeDraft {
    has source: str;
    has target: str;
}


obj WorkflowDraft {
    has source_event_type: str;
    has source_config_json: str = "{}";
    has run_mode: str = "once";
    has nodes: list[WorkflowNodeDraft] = [];
    has edges: list[WorkflowEdgeDraft] = [];
    has warnings: list[str] = [];
}


node WorkflowBlock {
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has config: dict = {};
    has custom_prompt: str = "";
    has status: str = "idle";
    has output: dict = {};
}


node SourceBlock(WorkflowBlock) {}
node LLMTransformBlock(WorkflowBlock) {}
node MacAppBlock(WorkflowBlock) {}
node MCPToolBlock(WorkflowBlock) {}
node OutputBlock(WorkflowBlock) {}


edge WorkflowFlow: WorkflowBlock --> WorkflowBlock {
    has source_port: str = "out";
    has target_port: str = "in";
}


walker WorkflowExecutorWalker {
    has ctx: dict = {};
    has ordered: list[BlockView] = [];
    has visited_ids: set[str] = set();
    has reports: list[list[BlockView]] = [];

    can begin with Root entry {
        print("[Swirl][Jac][Workflow] planning graph traversal");
        visit [-->[?:WorkflowBlock]];
    }

    def record(block: WorkflowBlock) -> bool {
        if block.id in self.visited_ids {
            return False;
        }
        self.visited_ids.add(block.id);
        block.status = "running";
        print(
            f"[Swirl][Jac][Workflow] planned node '{block.title}' ({block.category})"
        );
        self.ordered.append(
            BlockView(
                id=block.id,
                block_type=block.block_type,
                title=block.title,
                category=block.category,
                config=block.config,
                custom_prompt=block.custom_prompt,
                status=block.status,
                output=block.output,
            )
        );
        return True;
    }

    can execute_source with SourceBlock entry {
        self.record(here);
    }

    can execute_llm with LLMTransformBlock entry {
        self.record(here);
    }

    can execute_mac with MacAppBlock entry {
        self.record(here);
    }

    can execute_mcp with MCPToolBlock entry {
        print(
            f"[Swirl][Jac][MCP] server='{here.config.get('server', '')}' "
            f"tool='{here.config.get('tool_name', '')}'"
        );
        self.record(here);
    }

    can execute_output with OutputBlock entry {
        self.record(here);
    }

    can execute_base with WorkflowBlock entry {
        self.record(here);
    }

    can finish with Root exit {
        print(
            f"[Swirl][Jac][Workflow] graph plan ready ({len(self.ordered)} nodes)"
        );
        report self.ordered;
    }
}


walker PromptToWorkflowWalker {
    has user_prompt: str;
    has use_llm: bool = False;
    has generated: WorkflowAst | None = None;
    has reports: list[WorkflowAst] = [];

    can translate with Root entry {
        self.generated = (
            compile_llm_workflow(self.user_prompt)
            if self.use_llm
            else prompt_to_workflow_rules(self.user_prompt)
        );
    }

    can finish with Root exit {
        if self.generated is not None {
            report self.generated;
        }
    }
}


"""Translate intent into a typed workflow draft using Jac's configured LLM."""
def prompt_to_draft(user_prompt: str) -> WorkflowDraft by llm(
    temperature=0.1,
    max_tokens=2400,
    system_prompt="""Build a connected Swirl desktop workflow from the request.
Choose exactly one source_event_type from: trigger_email, trigger_file,
trigger_cron, trigger_clipboard, trigger_webhook, trigger_voice, trigger_sms.
Choose downstream block_type values only from: llm_summarize, llm_extract,
llm_classifier, mac_notes, mac_finder, mac_notification, mac_terminal,
mcp_fetch, mcp_fs, mcp_search, logic_if, output_slack.
Do not include a Source node in nodes. Use workflow-source as the source of
entry edges. Every downstream node must be reachable from workflow-source and
the graph must be acyclic. Encode each configuration object as valid JSON in
config_json/source_config_json. Preserve MCP server and tool_name settings.
Use these implemented configurations:
llm_summarize {prompt,maxTokens,temperature}; llm_extract
{prompt,extractSchema}; llm_classifier {prompt,categories};
mac_notes {app:"Notes",action:"create_note",folder,defaultTitle};
mac_finder {app:"Finder",action:"organize_by_extension",targetDirectory};
mac_notification {app:"System",action:"display_notification",sound};
mac_terminal {app:"Terminal",action:"exec_shell",command};
mcp_fetch {server:"fetch-mcp-server",tool_name:"fetch",url};
mcp_fs {server:"filesystem",tool_name:"read_text_file",path};
mcp_search {server:"brave-search-mcp",tool_name:"brave_web_search",query,maxResults};
logic_if {operator,matchString}; output_slack {webhookUrl,channel}.
Source configuration fields: email {mailbox,filterSubject,checkIntervalSec};
file {watchPath,filePattern,checkIntervalSec}; cron {cron,timezone};
clipboard {watchText,minChars,checkIntervalSec}; webhook
{host:"127.0.0.1",port,path,method:"POST",authRequired}; voice
{wakeWord,language,listenTimeoutSec}; sms
{phoneNumber:"8604644276",checkIntervalSec}.
Use run_mode continuous for whenever/monitor/watch/listen/every-time requests,
once for next/once/single-event requests, and once when ambiguous."""
);
sem prompt_to_draft = "Compile a natural-language automation request into a typed, connected Swirl workflow draft.";
sem prompt_to_draft.user_prompt = "The requested trigger, transformations, local tools, MCP tools, control flow, and outputs.";


def _json_object(encoded: str, label: str) -> dict {
    try {
        value: any = json.loads(encoded if encoded.strip() else "{}");
    } except Exception as error {
        raise ValueError(f"{label} must be valid JSON: {error}");
    }
    if not isinstance(value, dict) {
        raise ValueError(f"{label} must encode a JSON object");
    }
    return value as dict;
}


def _run_mode(user_prompt: str) -> str {
    lowered: str = user_prompt.lower();
    recurring: list[str] = [
        "whenever", "every time", "monitor", "watch", "listen",
        "continuously", "keep checking", "each time", "every day",
        "every morning", "every hour", "every minute", "daily"
    ];
    single: list[str] = [" next ", "once", "one time", "single event"];
    for phrase in recurring {
        if phrase in lowered {
            return "continuous";
        }
    }
    padded: str = " " + lowered + " ";
    for phrase in single {
        if phrase in padded {
            return "once";
        }
    }
    return "once";
}


def _block_catalog() -> dict[str, str] {
    return {
        "llm_summarize": "ai",
        "llm_extract": "ai",
        "llm_classifier": "ai",
        "mac_notes": "mac",
        "mac_finder": "mac",
        "mac_notification": "mac",
        "mac_terminal": "mac",
        "mcp_fetch": "mcp",
        "mcp_fs": "mcp",
        "mcp_search": "mcp",
        "logic_if": "logic",
        "output_slack": "output",
    };
}


def _block_defaults(block_type: str) -> dict {
    defaults: dict[str, dict] = {
        "llm_summarize": {
            "prompt": "Summarize concisely", "maxTokens": 500,
            "temperature": 0.2
        },
        "llm_extract": {"prompt": "Extract structured details", "extractSchema": "{}"},
        "llm_classifier": {"prompt": "Classify the input", "categories": ["other"]},
        "mac_notes": {
            "app": "Notes", "action": "create_note",
            "folder": "Swirl", "defaultTitle": "Swirl Workflow"
        },
        "mac_finder": {
            "app": "Finder", "action": "organize_by_extension",
            "targetDirectory": "~/Downloads"
        },
        "mac_notification": {
            "app": "System", "action": "display_notification", "sound": "Glass"
        },
        "mac_terminal": {
            "app": "Terminal", "action": "exec_shell", "command": "echo Swirl"
        },
        "mcp_fetch": {
            "server": "fetch-mcp-server", "tool_name": "fetch", "url": ""
        },
        "mcp_fs": {
            "server": "filesystem", "tool_name": "read_text_file",
            "path": "$SWIRL_DOCUMENTS"
        },
        "mcp_search": {
            "server": "brave-search-mcp", "tool_name": "brave_web_search",
            "query": "", "maxResults": 5
        },
        "logic_if": {"operator": "contains", "matchString": ""},
        "output_slack": {
            "webhookUrl": "https://hooks.slack.com/services/MOCK/SWIRL/KEY",
            "channel": "#automations"
        },
    };
    return defaults[block_type];
}


def _source_defaults(event_type: str) -> dict {
    defaults: dict[str, dict] = {
        "trigger_email": {
            "mailbox": "Inbox", "filterSubject": "",
            "checkIntervalSec": 15, "waitTimeoutSec": 0
        },
        "trigger_file": {
            "watchPath": "~/Downloads", "filePattern": "*",
            "checkIntervalSec": 2
        },
        "trigger_cron": {
            "cron": "*/15 * * * *", "timezone": "America/Los_Angeles"
        },
        "trigger_clipboard": {
            "watchText": True, "minChars": 1, "checkIntervalSec": 1
        },
        "trigger_webhook": {
            "host": "127.0.0.1", "port": 8787,
            "path": "/api/v1/webhook", "method": "POST",
            "authRequired": False
        },
        "trigger_voice": {
            "wakeWord": "Hey Swirl", "language": "en-US",
            "listenTimeoutSec": 30
        },
        "trigger_sms": {
            "phoneNumber": "8604644276", "checkIntervalSec": 1
        },
    };
    if event_type not in defaults {
        raise ValueError(f"Unsupported source event type: {event_type}");
    }
    return defaults[event_type];
}


def compile_llm_workflow(user_prompt: str) -> WorkflowAst {
    draft: WorkflowDraft = prompt_to_draft(user_prompt);
    return workflow_draft_to_ast(user_prompt, draft);
}


def workflow_draft_to_ast(
    user_prompt: str, draft: WorkflowDraft
) -> WorkflowAst {
    event_type: str = draft.source_event_type.strip();
    source_config: dict = _source_defaults(event_type) | _json_object(
        draft.source_config_json, "Source configuration"
    );
    source_config["eventType"] = event_type;
    source_config["runMode"] = _run_mode(user_prompt);
    nodes: list[dict] = [
        _node(
            "workflow-source", "source", "Source", "source", 32, 140,
            source_config
        )
    ];
    catalog: dict[str, str] = _block_catalog();
    ids: set[str] = {"workflow-source"};
    index: int = 0;
    for draft_node in draft.nodes {
        node_id: str = draft_node.id.strip();
        block_type: str = draft_node.block_type.strip();
        if not node_id or node_id == "workflow-source" {
            raise ValueError("Generated node IDs must be non-empty and cannot replace Source");
        }
        if node_id in ids {
            raise ValueError(f"Generated duplicate node ID: {node_id}");
        }
        if block_type not in catalog {
            raise ValueError(f"Unsupported generated block type: {block_type}");
        }
        ids.add(node_id);
        nodes.append(
            _node(
                node_id, block_type,
                draft_node.title.strip() or block_type,
                catalog[block_type], 392 + (index * 340),
                100 + ((index % 2) * 180),
                _block_defaults(block_type) | _json_object(
                    draft_node.config_json, f"Configuration for {node_id}"
                )
            )
        );
        index += 1;
    }
    if len(nodes) == 1 {
        raise ValueError("Jac LLM returned no executable workflow blocks");
    }

    edges: list[dict] = [];
    edge_index: int = 1;
    for draft_edge in draft.edges {
        source_id: str = draft_edge.source.strip();
        target_id: str = draft_edge.target.strip();
        if source_id not in ids or target_id not in ids {
            raise ValueError(
                f"Generated edge references an unknown node: {source_id} -> {target_id}"
            );
        }
        if target_id == "workflow-source" {
            raise ValueError("Source node cannot have incoming edges");
        }
        edges.append(_edge(f"edge-generated-{edge_index}", source_id, target_id));
        edge_index += 1;
    }
    workflow: dict = {"nodes": nodes, "edges": edges};
    # Planning performs cycle, connectivity, and Source-first ordering checks.
    plan_workflow(workflow);
    return WorkflowAst(
        nodes=nodes, edges=edges, source="llm", warnings=draft.warnings
    );
}


"""Transform workflow text using Jac's configured LLM."""
def transform_text(input_text: str, instruction: str) -> str by llm(
    temperature=0.2,
    max_tokens=800
);
sem transform_text = "Follow the instruction and transform the supplied workflow text.";
sem transform_text.input_text = "Text produced by the previous workflow graph node.";
sem transform_text.instruction = "The exact summarization, extraction, or classification instruction.";


def _node(
    node_id: str,
    block_type: str,
    title: str,
    category: str,
    x: int,
    y: int,
    config: dict,
) -> dict {
    normalized_type: str = block_type;
    normalized_title: str = title;
    normalized_category: str = category;
    normalized_config: dict = config;
    return {
        "id": node_id,
        "type": normalized_type,
        "title": normalized_title,
        "category": normalized_category,
        "jacNode": block_class_for(normalized_category),
        "x": x,
        "y": y,
        "config": normalized_config,
        "status": "idle",
    };
}


def _edge(edge_id: str, source: str, target: str) -> dict {
    return {
        "id": edge_id,
        "source": source,
        "target": target,
        "sourcePort": "out",
        "targetPort": "in",
    };
}


def block_class_for(category: str) -> str {
    classes: dict[str, str] = {
        "source": "SourceBlock",
        "ai": "LLMTransformBlock",
        "mac": "MacAppBlock",
        "mcp": "MCPToolBlock",
        "output": "OutputBlock",
    };
    return classes.get(category, "WorkflowBlock");
}


def prompt_to_workflow_rules(user_prompt: str) -> WorkflowAst {
    prompt: str = user_prompt.strip();
    lowered: str = prompt.lower();
    nodes: list[dict] = [];
    edges: list[dict] = [];

    if (
        "sms" in lowered or "text myself" in lowered
        or "text message" in lowered
    ) {
        nodes = [
            _node("workflow-source", "source", "Source", "source", 32, 140, {
                "eventType": "trigger_sms", "runMode": "continuous",
                "phoneNumber": "8604644276", "checkIntervalSec": 1
            }),
            _node("node-p1", "mac_notification", "Mac Notification", "mac", 440, 140, {
                "app": "System", "action": "display_notification", "sound": "Glass"
            }),
        ];
        edges = [
            _edge("edge-source-p1", "workflow-source", "node-p1"),
        ];
    } elif "email" in lowered or "mail" in lowered {
        nodes = [
            _node("workflow-source", "source", "Source", "source", 32, 140, {
                "eventType": "trigger_email", "runMode": _run_mode(prompt),
                "mailbox": "Inbox", "filterSubject": "",
                "checkIntervalSec": 15, "waitTimeoutSec": 0
            }),
            _node("node-p2", "llm_summarize", "LLM Summarizer", "ai", 440, 140, {
                "prompt": prompt, "maxTokens": 500, "temperature": 0.2
            }),
            _node("node-p3", "mac_notes", "Apple Notes", "mac", 800, 80, {
                "app": "Notes", "action": "create_note", "folder": "AI Summaries"
            }),
            _node("node-p4", "mac_notification", "Mac Notification", "mac", 800, 260, {
                "app": "System", "action": "display_notification", "sound": "Glass"
            }),
        ];
        edges = [
            _edge("edge-source-p2", "workflow-source", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
            _edge("edge-p2-p4", "node-p2", "node-p4"),
        ];
    } elif "desktop" in lowered or "finder" in lowered or "organize" in lowered {
        nodes = [
            _node("workflow-source", "source", "Source", "source", 32, 140, {
                "eventType": "trigger_file", "runMode": _run_mode(prompt),
                "watchPath": "~/Desktop", "filePattern": "*",
                "checkIntervalSec": 2
            }),
            _node("node-p2", "mac_finder", "Finder File Manager", "mac", 440, 140, {
                "app": "Finder", "action": "organize_by_extension",
                "targetDirectory": "~/Desktop"
            }),
            _node("node-p3", "mac_notes", "Apple Notes", "mac", 800, 140, {
                "app": "Notes", "action": "create_note",
                "folder": "Swirl Automations",
                "defaultTitle": "Desktop Organization Report"
            }),
        ];
        edges = [
            _edge("edge-source-p2", "workflow-source", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
        ];
    } else {
        nodes = [
            _node("workflow-source", "source", "Source", "source", 32, 140, {
                "eventType": "trigger_cron", "runMode": "continuous",
                "cron": "0 * * * *", "timezone": "America/Los_Angeles"
            }),
            _node("node-p2", "mcp_fetch", "MCP Web Scraper", "mcp", 440, 140, {
                "server": "fetch-mcp-server", "tool_name": "fetch",
                "url": "https://example.com"
            }),
            _node("node-p3", "llm_summarize", "LLM Summarizer", "ai", 800, 140, {
                "prompt": prompt, "maxTokens": 500, "temperature": 0.2
            }),
        ];
        edges = [
            _edge("edge-source-p2", "workflow-source", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
        ];
    }
    return WorkflowAst(nodes=nodes, edges=edges, source="rules");
}


def instantiate_block(spec: dict) -> WorkflowBlock {
    node_id: str = str(spec.get("id", ""));
    block_type: str = str(spec.get("type", "unknown"));
    title: str = str(spec.get("title", block_type));
    category: str = str(spec.get("category", ""));
    config: dict = spec.get("config", {}) as dict;
    custom_prompt: str = str(spec.get("customPrompt", ""));

    if category == "source" {
        return SourceBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
    } elif category == "ai" {
        return LLMTransformBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
    } elif category == "mac" {
        return MacAppBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
    } elif category == "mcp" {
        return MCPToolBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
    } elif category == "output" {
        return OutputBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
    }
    return WorkflowBlock(id=node_id, block_type=block_type, title=title, category=category, config=config, custom_prompt=custom_prompt);
}


def plan_workflow(workflow: dict) -> list[dict] {
    specs: list = workflow.get("nodes", []) as list;
    edge_specs: list = workflow.get("edges", []) as list;
    by_id: dict[str, WorkflowBlock] = {};
    incoming: dict[str, int] = {};
    outgoing: dict[str, list[str]] = {};
    source_id: str = "";
    source_count: int = 0;

    for raw_spec in specs {
        spec: dict = raw_spec as dict;
        block: WorkflowBlock = instantiate_block(spec);
        by_id[block.id] = block;
        incoming[block.id] = 0;
        outgoing[block.id] = [];
        if block.category == "source" {
            source_count += 1;
            source_id = block.id;
        }
    }
    if source_count != 1 {
        raise ValueError(
            f"Workflow must contain exactly one source node (found {source_count})"
        );
    }

    for raw_edge in edge_specs {
        edge_spec: dict = raw_edge as dict;
        edge_source: str = str(edge_spec.get("source", ""));
        target_id: str = str(edge_spec.get("target", ""));
        if edge_source not in by_id or target_id not in by_id {
            raise ValueError(f"Edge references unknown node: {edge_source} -> {target_id}");
        }
        if target_id == source_id {
            raise ValueError("Source node cannot have incoming edges");
        }
        by_id[edge_source] ++> by_id[target_id];
        incoming[target_id] += 1;
        outgoing[edge_source].append(target_id);
    }

    ready: list[str] = [source_id];
    for block_id in by_id {
        if block_id != source_id and incoming[block_id] == 0 {
            raise ValueError("Every workflow node must be reachable from Source");
        }
    }
    ordered_ids: list[str] = [];
    cursor: int = 0;
    while cursor < len(ready) {
        current_id: str = ready[cursor];
        cursor += 1;
        ordered_ids.append(current_id);
        for target_id in outgoing[current_id] {
            incoming[target_id] -= 1;
            if incoming[target_id] == 0 {
                ready.append(target_id);
            }
        }
    }
    if len(ordered_ids) != len(by_id) {
        raise ValueError("Workflow contains a cycle or unreachable node");
    }
    views: list[dict] = [];
    print("[Swirl][Jac][Workflow] preparing deterministic execution plan");
    for block_id in ordered_ids {
        block: WorkflowBlock = by_id[block_id];
        block.status = "running";
        if block.category == "mcp" {
            print(
                f"[Swirl][Jac][MCP] server='{block.config.get('server', '')}' "
                f"tool='{block.config.get('tool_name', '')}'"
            );
        }
        print(
            f"[Swirl][Jac][Workflow] planned node '{block.title}' "
            f"({block.category})"
        );
        views.append(
            BlockView(
                id=block.id,
                block_type=block.block_type,
                title=block.title,
                category=block.category,
                config=block.config,
                custom_prompt=block.custom_prompt,
                status=block.status,
                output=block.output,
            ).to_dict()
        );
    }
    print(
        f"[Swirl][Jac][Workflow] deterministic plan ready "
        f"({len(views)} nodes)"
    );
    return views;
}


def utc_now_iso() -> str {
    return datetime.now(timezone.utc).isoformat();
}
