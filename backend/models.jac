"""
Models for the Swirl backend.
"""

obj WorkflowNode {
    """Represents a node in a workflow graph."""
    has id: str;
    has block_type: str;
    has title: str;
    has category: str;
    has jac_node: str = "";
    has config: dict;
}

obj WorkflowEdge {
    """Represents a directed edge between workflow nodes."""
    has id: str;
    has source: str;
    has target: str;
    has source_port: str = "out";
    has target_port: str = "in";
}

obj WorkflowDocument {
    """A complete workflow with nodes and edges."""
    has nodes: list[dict];
    has edges: list[dict];

    def validate() -> None {
        """Validates the workflow document for correctness."""
        if not self.nodes {
            raise ValueError("Workflow must contain at least one node");
        }
        if len(self.nodes) > 500 {
            raise ValueError("Workflow exceeds the 500-node safety limit");
        }
        
        ids = set();
        for node in self.nodes {
            node_id = node.get("id", "");
            if not node_id.strip() {
                raise ValueError("Workflow node IDs cannot be empty");
            }
            if node_id in ids {
                raise ValueError(f"Duplicate workflow node ID: {node_id}");
            }
            ids.add(node_id);
            if len(node.get("title", "")) > 200 {
                raise ValueError(f"Node title is too long: {node_id}");
            }
        }
        
        # Kahn's algorithm for cycle detection (topological sort)
        indegree = {n.get("id"): 0 for n in self.nodes};
        outgoing = {};
        
        for edge in self.edges {
            edge_id = edge.get("id", "");
            source = edge.get("source", "");
            target = edge.get("target", "");
            
            if source not in ids or target not in ids {
                raise ValueError(f"Edge {edge_id} references an unknown node: {source} -> {target}");
            }
            if source == target {
                raise ValueError(f"Self-referencing edge is not allowed: {edge_id}");
            }
            
            indegree[target] += 1;
            if source not in outgoing {
                outgoing[source] = [];
            }
            outgoing[source].append(target);
        }
        
        queue = [n_id for n_id, deg in indegree.items() if deg == 0];
        cursor = 0;
        
        while cursor < len(queue) {
            current = queue[cursor];
            cursor += 1;
            
            if current in outgoing {
                for target in outgoing[current] {
                    indegree[target] -= 1;
                    if indegree[target] == 0 {
                        queue.append(target);
                    }
                }
            }
        }
        
        if len(queue) != len(self.nodes) {
            raise ValueError("Workflow graph contains a cycle");
        }
    }
}

obj WorkflowExecutionRequest {
    """A request to execute a workflow."""
    has workflow: WorkflowDocument;
    has context: dict;
    has approvals: set[str];
}

obj ExecutionEvent {
    """An event emitted during workflow execution."""
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
            "output": self.output
        };
    }
}

obj ExecutionSummary {
    """Summary of a completed workflow execution."""
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
            "failed_node_id": self.failed_node_id
        };
    }
}

test "validates a valid DAG" {
    nodes = [{"id": "a", "title": "A"}, {"id": "b", "title": "B"}];
    edges = [{"id": "e1", "source": "a", "target": "b"}];
    doc = WorkflowDocument(nodes=nodes, edges=edges);
    doc.validate();
}

test "rejects cycles" {
    nodes = [{"id": "a", "title": "A"}, {"id": "b", "title": "B"}];
    edges = [{"id": "e1", "source": "a", "target": "b"}, {"id": "e2", "source": "b", "target": "a"}];
    doc = WorkflowDocument(nodes=nodes, edges=edges);
    try {
        doc.validate();
        assert False;
    } except ValueError as e {
        assert "cycle" in str(e);
    }
}

test "rejects unknown edge targets" {
    nodes = [{"id": "a", "title": "A"}];
    edges = [{"id": "e1", "source": "a", "target": "b"}];
    doc = WorkflowDocument(nodes=nodes, edges=edges);
    try {
        doc.validate();
        assert False;
    } except ValueError as e {
        assert "unknown node" in str(e);
    }
}

test "rejects self-referencing edges" {
    nodes = [{"id": "a", "title": "A"}];
    edges = [{"id": "e1", "source": "a", "target": "a"}];
    doc = WorkflowDocument(nodes=nodes, edges=edges);
    try {
        doc.validate();
        assert False;
    } except ValueError as e {
        assert "Self-referencing" in str(e);
    }
}

test "rejects duplicate node IDs" {
    nodes = [{"id": "a", "title": "A"}, {"id": "a", "title": "B"}];
    edges = [];
    doc = WorkflowDocument(nodes=nodes, edges=edges);
    try {
        doc.validate();
        assert False;
    } except ValueError as e {
        assert "Duplicate" in str(e);
    }
}

test "rejects empty workflow" {
    doc = WorkflowDocument(nodes=[], edges=[]);
    try {
        doc.validate();
        assert False;
    } except ValueError as e {
        assert "at least one node" in str(e);
    }
}
