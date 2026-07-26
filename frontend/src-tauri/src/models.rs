use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct WorkflowPosition {
    pub x: f64,
    pub y: f64,
}

impl Default for WorkflowPosition {
    fn default() -> Self {
        Self { x: 250.0, y: 180.0 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowNode {
    pub id: String,
    #[serde(rename = "type")]
    pub block_type: String,
    pub title: String,
    pub category: String,
    #[serde(default)]
    pub jac_node: Option<String>,
    #[serde(default)]
    pub config: Value,
    #[serde(default)]
    pub position: WorkflowPosition,
    #[serde(default)]
    pub custom_prompt: String,
    // Legacy layout fields are read from older workflow files and migrated before
    // a record is returned or persisted again.
    #[serde(default, rename = "x", skip_serializing)]
    legacy_x: Option<f64>,
    #[serde(default, rename = "y", skip_serializing)]
    legacy_y: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowEdge {
    pub id: String,
    pub source: String,
    pub target: String,
    #[serde(default)]
    pub source_port: Option<String>,
    #[serde(default)]
    pub target_port: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowDocument {
    pub nodes: Vec<WorkflowNode>,
    #[serde(default)]
    pub edges: Vec<WorkflowEdge>,
}

impl WorkflowDocument {
    pub fn migrate_legacy_layout(&mut self) {
        for node in &mut self.nodes {
            if let (Some(x), Some(y)) = (node.legacy_x, node.legacy_y) {
                node.position = WorkflowPosition { x, y };
            }
            node.legacy_x = None;
            node.legacy_y = None;
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.nodes.is_empty() {
            return Err("Workflow must contain at least one node".into());
        }
        if self.nodes.len() > 500 {
            return Err("Workflow exceeds the 500-node safety limit".into());
        }

        let supported_blocks = [
            "on_run", "source", "output", "mac_wait_email", "llm_summarize", "mac_notes", "mac_finder",
            "mac_notification", "mac_terminal", "mcp_fetch", "mcp_fs", "mcp_search",
            "output_slack",
        ];
        let mut ids = HashSet::new();
        let source_count = self
            .nodes
            .iter()
            .filter(|node| node.category == "source")
            .count();
        if source_count != 1 {
            return Err(format!(
                "Workflow must contain exactly one source node (found {source_count})"
            ));
        }
        for node in &self.nodes {
            if !supported_blocks.contains(&node.block_type.as_str()) {
                return Err(format!(
                    "Unsupported legacy block type: {}. Remove it and use a supported block.",
                    node.block_type
                ));
            }
            if node.id.trim().is_empty() {
                return Err("Workflow node IDs cannot be empty".into());
            }
            if !ids.insert(node.id.as_str()) {
                return Err(format!("Duplicate workflow node ID: {}", node.id));
            }
            if node.title.len() > 200 {
                return Err(format!("Node title is too long: {}", node.id));
            }
        }

        let mut indegree: HashMap<&str, usize> = self
            .nodes
            .iter()
            .map(|node| (node.id.as_str(), 0))
            .collect();
        let mut outgoing: HashMap<&str, Vec<&str>> = HashMap::new();
        for edge in &self.edges {
            if !ids.contains(edge.source.as_str()) || !ids.contains(edge.target.as_str()) {
                return Err(format!(
                    "Edge {} references an unknown node: {} -> {}",
                    edge.id, edge.source, edge.target
                ));
            }
            if edge.source == edge.target {
                return Err(format!("Self-referencing edge is not allowed: {}", edge.id));
            }
            if self
                .nodes
                .iter()
                .any(|node| node.id == edge.target && node.category == "source")
            {
                return Err("Source node cannot have incoming edges".into());
            }
            *indegree
                .get_mut(edge.target.as_str())
                .expect("validated target") += 1;
            outgoing
                .entry(edge.source.as_str())
                .or_default()
                .push(edge.target.as_str());
        }

        let mut queue: Vec<&str> = indegree
            .iter()
            .filter_map(|(id, degree)| (*degree == 0).then_some(*id))
            .collect();
        let mut cursor = 0;
        while cursor < queue.len() {
            let current = queue[cursor];
            cursor += 1;
            if let Some(targets) = outgoing.get(current) {
                for target in targets {
                    let degree = indegree.get_mut(target).expect("validated target");
                    *degree -= 1;
                    if *degree == 0 {
                        queue.push(target);
                    }
                }
            }
        }
        if queue.len() != self.nodes.len() {
            return Err("Workflow graph contains a cycle".into());
        }
        let roots = self.nodes.iter()
            .filter(|node| node.category == "source")
            .map(|node| node.id.as_str())
            .collect::<Vec<_>>();
        let mut reachable = roots.iter().copied().collect::<HashSet<_>>();
        let mut traversal = roots;
        let mut cursor = 0;
        while cursor < traversal.len() {
            let current = traversal[cursor];
            cursor += 1;
            if let Some(targets) = outgoing.get(current) {
                for target in targets {
                    if reachable.insert(*target) {
                        traversal.push(*target);
                    }
                }
            }
        }
        if reachable.len() != self.nodes.len() {
            return Err("Every workflow node must be reachable from Source".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn node(id: &str) -> WorkflowNode {
        WorkflowNode {
            id: id.into(),
            block_type: "source".into(),
            title: id.into(),
            category: "source".into(),
            jac_node: None,
            config: json!({}),
            position: WorkflowPosition::default(),
            custom_prompt: String::new(),
            legacy_x: None,
            legacy_y: None,
        }
    }

    fn edge(id: &str, source: &str, target: &str) -> WorkflowEdge {
        WorkflowEdge {
            id: id.into(),
            source: source.into(),
            target: target.into(),
            source_port: None,
            target_port: None,
        }
    }

    #[test]
    fn validates_a_dag() {
        let workflow = WorkflowDocument {
            nodes: vec![
                node("a"),
                WorkflowNode {
                    category: "output".into(),
                    ..node("b")
                },
            ],
            edges: vec![edge("a-b", "a", "b")],
        };
        assert!(workflow.validate().is_ok());
    }

    #[test]
    fn rejects_cycles() {
        let workflow = WorkflowDocument {
            nodes: vec![
                node("source"),
                WorkflowNode {
                    category: "output".into(),
                    ..node("a")
                },
                WorkflowNode {
                    category: "output".into(),
                    ..node("b")
                },
            ],
            edges: vec![edge("a-b", "a", "b"), edge("b-a", "b", "a")],
        };
        assert_eq!(
            workflow.validate().unwrap_err(),
            "Workflow graph contains a cycle"
        );
    }

    #[test]
    fn rejects_unknown_edge_targets() {
        let workflow = WorkflowDocument {
            nodes: vec![node("a")],
            edges: vec![edge("a-missing", "a", "missing")],
        };
        assert!(workflow
            .validate()
            .unwrap_err()
            .contains("references an unknown node"));
    }

    #[test]
    fn rejects_removed_legacy_blocks() {
        let workflow = WorkflowDocument {
            nodes: vec![
                node("start"),
                WorkflowNode {
                    block_type: "trigger_cron".into(),
                    category: "trigger".into(),
                    ..node("legacy")
                },
            ],
            edges: vec![edge("start-legacy", "start", "legacy")],
        };
        assert!(workflow
            .validate()
            .unwrap_err()
            .contains("Unsupported legacy block type: trigger_cron"));
    }

    #[test]
    fn rejects_missing_and_duplicate_sources() {
        let missing = WorkflowDocument {
            nodes: vec![WorkflowNode {
                category: "output".into(),
                ..node("result")
            }],
            edges: Vec::new(),
        };
        assert!(missing
            .validate()
            .unwrap_err()
            .contains("exactly one source"));

        let duplicate = WorkflowDocument {
            nodes: vec![node("source-a"), node("source-b")],
            edges: Vec::new(),
        };
        assert!(duplicate
            .validate()
            .unwrap_err()
            .contains("exactly one source"));
    }

    #[test]
    fn rejects_an_incoming_edge_to_source() {
        let workflow = WorkflowDocument {
            nodes: vec![
                node("source"),
                WorkflowNode {
                    category: "output".into(),
                    ..node("result")
                },
            ],
            edges: vec![edge("result-source", "result", "source")],
        };
        assert_eq!(
            workflow.validate().unwrap_err(),
            "Source node cannot have incoming edges"
        );
    }

    #[test]
    fn rejects_nodes_disconnected_from_source() {
        let workflow = WorkflowDocument {
            nodes: vec![
                node("source"),
                WorkflowNode {
                    category: "output".into(),
                    ..node("result")
                },
            ],
            edges: Vec::new(),
        };
        assert_eq!(
            workflow.validate().unwrap_err(),
            "Every workflow node must be reachable from Source"
        );
    }

    #[test]
    fn migrates_legacy_layout_and_serializes_persistence_fields() {
        let mut workflow: WorkflowDocument = serde_json::from_value(json!({
            "nodes": [
                {
                    "id": "workflow-source", "type": "source", "title": "Source",
                    "category": "source", "config": {}, "x": 48, "y": 96
                },
                {
                    "id": "ai", "type": "llm_summarize", "title": "AI",
                    "category": "ai", "config": {},
                    "position": { "x": 420, "y": 128 },
                    "customPrompt": "Return only action items"
                }
            ],
            "edges": [{
                "id": "source-ai", "source": "workflow-source", "target": "ai",
                "sourcePort": "event", "targetPort": "text"
            }]
        }))
        .unwrap();

        workflow.migrate_legacy_layout();
        assert_eq!(
            workflow.nodes[0].position,
            WorkflowPosition { x: 48.0, y: 96.0 }
        );
        assert_eq!(workflow.nodes[1].custom_prompt, "Return only action items");
        assert_eq!(workflow.edges[0].source_port.as_deref(), Some("event"));
        assert_eq!(workflow.edges[0].target_port.as_deref(), Some("text"));

        let serialized = serde_json::to_value(workflow).unwrap();
        assert!(serialized["nodes"][0].get("x").is_none());
        assert_eq!(serialized["nodes"][0]["position"]["x"], 48.0);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowExecutionRequest {
    #[serde(flatten)]
    pub workflow: WorkflowDocument,
    #[serde(default)]
    pub context: Value,
    #[serde(default)]
    pub approvals: HashSet<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionEvent {
    pub event: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub iteration: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionSummary {
    pub success: bool,
    pub context: Value,
    pub results: HashMap<String, Value>,
    pub completed_node_ids: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failed_node_id: Option<String>,
}
