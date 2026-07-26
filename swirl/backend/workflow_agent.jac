"""Swirl's graph-native workflow model and agent walkers."""

import json;
import from datetime { datetime, timezone }


obj BlockView {
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has config: dict = {};
    has status: str = "idle";
    has output: dict = {};

    def to_dict() -> dict {
        return {
            "id": self.id,
            "type": self.block_type,
            "title": self.title,
            "category": self.category,
            "config": self.config,
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


node WorkflowBlock {
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has config: dict = {};
    has status: str = "idle";
    has output: dict = {};
}


node SourceBlock(WorkflowBlock) {}
node TriggerBlock(WorkflowBlock) {}
node LLMTransformBlock(WorkflowBlock) {}
node MacAppBlock(WorkflowBlock) {}
node MCPToolBlock(WorkflowBlock) {}
node ConditionBlock(WorkflowBlock) {}
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
        visit [-->[?:WorkflowBlock]];
    }

    def record(block: WorkflowBlock) -> bool {
        if block.id in self.visited_ids {
            return False;
        }
        self.visited_ids.add(block.id);
        block.status = "running";
        self.ordered.append(
            BlockView(
                id=block.id,
                block_type=block.block_type,
                title=block.title,
                category=block.category,
                config=block.config,
                status=block.status,
                output=block.output,
            )
        );
        return True;
    }

    can execute_source with SourceBlock entry {
        self.record(here);
    }

    can execute_trigger with TriggerBlock entry {
        self.record(here);
    }

    can execute_llm with LLMTransformBlock entry {
        self.record(here);
    }

    can execute_mac with MacAppBlock entry {
        self.record(here);
    }

    can execute_mcp with MCPToolBlock entry {
        self.record(here);
    }

    can execute_condition with ConditionBlock entry {
        self.record(here);
    }

    can execute_output with OutputBlock entry {
        self.record(here);
    }

    can execute_base with WorkflowBlock entry {
        self.record(here);
    }

    can finish with Root exit {
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
            prompt_to_ast(self.user_prompt)
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


"""Translate intent into a workflow AST using Jac's configured LLM."""
def prompt_to_ast(user_prompt: str) -> WorkflowAst by llm(
    temperature=0.1,
    max_tokens=1800,
    system_prompt="Return a safe Swirl workflow graph with exactly one source node at the leftmost entry. Use source, ai, mac, mcp, logic, and output categories. The source config must contain eventType equal to trigger_email, trigger_file, or trigger_cron. Return connected nodes and edges only."
);
sem prompt_to_ast = "Compile a natural-language desktop automation request into a connected Swirl workflow AST.";
sem prompt_to_ast.user_prompt = "The user's requested automation, including triggers, transformations, tools, and outputs.";


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
    if category == "trigger" {
        normalized_type = "source";
        normalized_title = "Source";
        normalized_category = "source";
        normalized_config = {"eventType": block_type} | config;
    }
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
        "trigger": "TriggerBlock",
        "ai": "LLMTransformBlock",
        "mac": "MacAppBlock",
        "mcp": "MCPToolBlock",
        "logic": "ConditionBlock",
        "output": "OutputBlock",
    };
    return classes.get(category, "WorkflowBlock");
}


def prompt_to_workflow_rules(user_prompt: str) -> WorkflowAst {
    prompt: str = user_prompt.strip();
    lowered: str = prompt.lower();
    nodes: list[dict] = [];
    edges: list[dict] = [];

    if "email" in lowered or "mail" in lowered {
        nodes = [
            _node("node-p1", "trigger_email", "On Email Received", "trigger", 80, 140, {
                "mailbox": "Inbox", "filterSubject": ""
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
            _edge("edge-p1-p2", "node-p1", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
            _edge("edge-p2-p4", "node-p2", "node-p4"),
        ];
    } elif "desktop" in lowered or "finder" in lowered or "organize" in lowered {
        nodes = [
            _node("node-p1", "trigger_file", "On File Created", "trigger", 80, 140, {
                "watchPath": "~/Desktop", "filePattern": "*"
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
            _edge("edge-p1-p2", "node-p1", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
        ];
    } elif "calendar" in lowered or "meeting" in lowered or "event" in lowered {
        nodes = [
            _node("node-p1", "trigger_cron", "Cron Schedule", "trigger", 80, 140, {
                "cron": "0 9 * * *", "timezone": "America/Los_Angeles"
            }),
            _node("node-p2", "llm_extract", "LLM Entity Extractor", "ai", 440, 140, {
                "prompt": prompt,
                "extractSchema": "{\"title\":\"\",\"start\":\"\",\"end\":\"\"}"
            }),
            _node("node-p3", "mac_calendar", "Apple Calendar", "mac", 800, 140, {
                "app": "Calendar", "action": "create_event"
            }),
        ];
        edges = [
            _edge("edge-p1-p2", "node-p1", "node-p2"),
            _edge("edge-p2-p3", "node-p2", "node-p3"),
        ];
    } else {
        nodes = [
            _node("node-p1", "trigger_cron", "Cron Schedule", "trigger", 80, 140, {
                "cron": "0 * * * *", "timezone": "America/Los_Angeles"
            }),
            _node("node-p2", "mcp_fetch", "MCP Web Scraper", "mcp", 440, 140, {
                "server": "fetch-mcp-server", "tool_name": "fetch_url",
                "params": {"url": ""}
            }),
            _node("node-p3", "llm_summarize", "LLM Summarizer", "ai", 800, 140, {
                "prompt": prompt, "maxTokens": 500, "temperature": 0.2
            }),
        ];
        edges = [
            _edge("edge-p1-p2", "node-p1", "node-p2"),
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

    if category == "source" {
        return SourceBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "trigger" {
        return TriggerBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "ai" {
        return LLMTransformBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "mac" {
        return MacAppBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "mcp" {
        return MCPToolBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "logic" {
        return ConditionBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    } elif category == "output" {
        return OutputBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
    }
    return WorkflowBlock(id=node_id, block_type=block_type, title=title, category=category, config=config);
}


def plan_workflow(workflow: dict) -> list[dict] {
    specs: list = workflow.get("nodes", []) as list;
    edge_specs: list = workflow.get("edges", []) as list;
    by_id: dict[str, WorkflowBlock] = {};
    incoming: dict[str, int] = {};
    outgoing: dict[str, list[str]] = {};

    for raw_spec in specs {
        spec: dict = raw_spec as dict;
        block: WorkflowBlock = instantiate_block(spec);
        by_id[block.id] = block;
        incoming[block.id] = 0;
        outgoing[block.id] = [];
    }

    for raw_edge in edge_specs {
        edge_spec: dict = raw_edge as dict;
        source_id: str = str(edge_spec.get("source", ""));
        target_id: str = str(edge_spec.get("target", ""));
        if source_id not in by_id or target_id not in by_id {
            raise ValueError(f"Edge references unknown node: {source_id} -> {target_id}");
        }
        by_id[source_id] ++> by_id[target_id];
        incoming[target_id] += 1;
        outgoing[source_id].append(target_id);
    }

    ready: list[str] = [];
    for block_id in by_id {
        if incoming[block_id] == 0 {
            ready.append(block_id);
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
    for block_id in ordered_ids {
        root ++> by_id[block_id];
    }

    result = root spawn WorkflowExecutorWalker();
    views: list[BlockView] = result.reports[0] if result.reports else [];
    return [view.to_dict() for view in views];
}


def utc_now_iso() -> str {
    return datetime.now(timezone.utc).isoformat();
}
