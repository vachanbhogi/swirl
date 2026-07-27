"""Shared Jac data models for canonical source-based workflows."""

glob SUPPORTED_BLOCKS: set[str] = {
    "on_run",
    "source",
    "output",
    "mac_wait_email",
    "llm_summarize",
    "mac_notes",
    "mac_finder",
    "mac_notification",
    "mac_terminal",
    "mcp_fetch",
    "mcp_fs",
    "mcp_search",
    "output_slack",
};

glob GENERATED_SOURCE_EVENTS: set[str] = {
    "trigger_email",
    "trigger_file",
    "trigger_cron",
    "trigger_clipboard",
    "trigger_webhook",
    "trigger_voice",
    "trigger_sms",
};

glob GENERATED_BLOCK_PAIRS: set[str] = {
    "llm_summarize:ai",
    "llm_extract:ai",
    "llm_classifier:ai",
    "mac_notes:mac",
    "mac_finder:mac",
    "mac_notification:mac",
    "mac_terminal:mac",
    "mcp_fetch:mcp",
    "mcp_fs:mcp",
    "mcp_search:mcp",
    "logic_if:logic",
    "output_slack:output",
};


obj WorkflowNode {
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has config: dict = {};
    has jac_node: str = "";
}


obj WorkflowEdge {
    has id: str;
    has source: str;
    has target: str;
    has source_port: str = "out";
    has target_port: str = "in";
}


obj WorkflowDocument {
    has nodes: list[dict];
    has edges: list[dict] = [];

    def validate() {
        if not self.nodes {
            raise ValueError("Workflow must contain at least one node");
        }
        if len(self.nodes) > 500 {
            raise ValueError("Workflow exceeds the 500-node safety limit");
        }

        ids: set[str] = set();
        categories: dict[str, str] = {};
        source_count: int = 0;
        source_id: str = "";
        for node in self.nodes {
            node_id: str = str(node.get("id", ""));
            block_type: str = str(node.get("type", ""));
            if block_type not in SUPPORTED_BLOCKS {
                raise ValueError(
                    "Unsupported legacy block type: "
                    + block_type
                    + ". Remove it and use a supported block."
                );
            }
            if not node_id.strip() {
                raise ValueError("Workflow node IDs cannot be empty");
            }
            if node_id in ids {
                raise ValueError(f"Duplicate workflow node ID: {node_id}");
            }
            ids.add(node_id);
            categories[node_id] = str(node.get("category", ""));
            if len(str(node.get("title", ""))) > 200 {
                raise ValueError(f"Node title is too long: {node_id}");
            }
            category: str = str(node.get("category", ""));
            if category == "source" {
                source_count += 1;
                source_id = node_id;
            }
        }
        if source_count != 1 {
            raise ValueError(
                f"Workflow must contain exactly one source node (found {source_count})"
            );
        }

        indegree: dict[str, int] = {};
        outgoing: dict[str, list[str]] = {};
        for node_id in ids {
            indegree[node_id] = 0;
            outgoing[node_id] = [];
        }
        for edge in self.edges {
            edge_id: str = str(edge.get("id", ""));
            edge_source: str = str(edge.get("source", ""));
            target: str = str(edge.get("target", ""));
            if edge_source not in ids or target not in ids {
                raise ValueError(
                    f"Edge {edge_id} references an unknown node: {edge_source} -> {target}"
                );
            }
            if edge_source == target {
                raise ValueError(
                    f"Self-referencing edge is not allowed: {edge_id}"
                );
            }
            target_category: str = categories[target];
            if target_category == "source" {
                raise ValueError("Source node cannot have incoming edges");
            }
            indegree[target] += 1;
            outgoing[edge_source].append(target);
        }

        queue: list[str] = [];
        for node_id in ids {
            if indegree[node_id] == 0 {
                queue.append(node_id);
            }
        }
        cursor: int = 0;
        while cursor < len(queue) {
            current: str = queue[cursor];
            cursor += 1;
            for target in outgoing[current] {
                indegree[target] -= 1;
                if indegree[target] == 0 {
                    queue.append(target);
                }
            }
        }
        if len(queue) != len(self.nodes) {
            raise ValueError("Workflow graph contains a cycle");
        }
        roots: list[str] = [str(node.get("id", "")) for node in self.nodes if node.get("category") == "source" or node.get("category") == "trigger"];
        reachable: set[str] = set(roots);
        traversal: list[str] = roots;
        cursor = 0;
        while cursor < len(traversal) {
            current: str = traversal[cursor];
            cursor += 1;
            for target in outgoing[current] {
                if target not in reachable {
                    reachable.add(target);
                    traversal.append(target);
                }
            }
        }
        if len(reachable) != len(self.nodes) {
            raise ValueError(
                "Every workflow node must be reachable from Source"
            );
        }
    }
}


def validate_workflow(workflow: dict) -> dict {
    document = WorkflowDocument(
        nodes=workflow.get("nodes", []) as list[dict],
        edges=workflow.get("edges", []) as list[dict],
    );
    document.validate();
    return {"valid": True};
}


def validate_generated_workflow(workflow: dict) -> dict {
    validate_workflow(workflow);
    nodes: list[dict] = workflow.get("nodes", []) as list[dict];
    for node in nodes {
        category: str = str(node.get("category", ""));
        block_type: str = str(node.get("type", ""));
        if category == "source" {
            config: dict = node.get("config", {}) as dict;
            event_type: str = str(config.get("eventType", ""));
            if block_type != "source" or event_type not in GENERATED_SOURCE_EVENTS {
                raise ValueError(
                    f"Unsupported generated Source event: {event_type}"
                );
            }
            run_mode: str = str(config.get("runMode", "once"));
            if run_mode not in {"once", "continuous"} {
                raise ValueError(
                    f"Unsupported generated Source run mode: {run_mode}"
                );
            }
        } elif f"{block_type}:{category}" not in GENERATED_BLOCK_PAIRS {
            raise ValueError(
                "Unsupported generated block/category pair: "
                + block_type
                + "/"
                + category
            );
        }
    }
    return {"valid": True};
}


obj WorkflowExecutionRequest {
    has workflow: WorkflowDocument;
    has context: dict = {};
    has approvals: set[str] = set();
}


obj ExecutionEvent {
    has event: str;
    has node_id: str = "";
    has title: str = "";
    has status: str = "";
    has message: str = "";
    has output: dict = {};

    def to_dict() -> dict {
        return {
            "event": self.event,
            "node_id": self.node_id,
            "title": self.title,
            "status": self.status,
            "message": self.message,
            "output": self.output,
        };
    }
}


obj ExecutionSummary {
    has success: bool;
    has context: dict;
    has results: dict;
    has completed_node_ids: list[str];
    has failed_node_id: str = "";

    def to_dict() -> dict {
        return {
            "success": self.success,
            "context": self.context,
            "results": self.results,
            "completed_node_ids": self.completed_node_ids,
            "failed_node_id": self.failed_node_id,
        };
    }
}


def source_node(node_id: str = "source") -> dict {
    return {
        "id": node_id,
        "type": "source",
        "title": "On Run",
        "category": "source",
        "config": {},
    };
}


def action_node(node_id: str, category: str = "ai") -> dict {
    return {
        "id": node_id,
        "type": "llm_summarize" if category == "ai" else "output",
        "title": node_id,
        "category": category,
        "config": {},
    };
}


test "validates a source-based DAG" {
    nodes: list[dict] = [
        source_node(),
        action_node("b"),
    ];
    edges: list[dict] = [
        {"id": "e1", "source": "source", "target": "b"},
    ];
    WorkflowDocument(nodes=nodes, edges=edges).validate();
}


test "rejects cycles" {
    nodes: list[dict] = [
        source_node(),
        action_node("a"),
        action_node("b"),
    ];
    edges: list[dict] = [
        {"id": "e1", "source": "source", "target": "a"},
        {"id": "e2", "source": "a", "target": "b"},
        {"id": "e3", "source": "b", "target": "a"},
    ];
    try {
        WorkflowDocument(nodes=nodes, edges=edges).validate();
        assert False;
    } except ValueError as error {
        assert "cycle" in str(error);
    }
}


test "rejects incoming source edges" {
    nodes: list[dict] = [
        source_node(),
        action_node("a"),
    ];
    edges: list[dict] = [
        {"id": "e1", "source": "a", "target": "source"},
    ];
    try {
        WorkflowDocument(nodes=nodes, edges=edges).validate();
        assert False;
    } except ValueError as error {
        assert "incoming" in str(error);
    }
}


test "rejects missing source" {
    try {
        WorkflowDocument(
            nodes=[action_node("a")],
            edges=[],
        ).validate();
        assert False;
    } except ValueError as error {
        assert "exactly one source" in str(error);
    }
}


test "rejects duplicate source" {
    try {
        WorkflowDocument(
            nodes=[source_node("a"), source_node("b")],
            edges=[],
        ).validate();
        assert False;
    } except ValueError as error {
        assert "exactly one source" in str(error);
    }
}


test "rejects nodes disconnected from source" {
    try {
        WorkflowDocument(
            nodes=[
                source_node(),
                action_node("result", "output"),
            ],
            edges=[],
        ).validate();
        assert False;
    } except ValueError as error {
        assert "reachable from Source" in str(error);
    }
}
