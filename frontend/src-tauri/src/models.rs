use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

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
    pub fn validate(&self) -> Result<(), String> {
        if self.nodes.is_empty() {
            return Err("Workflow must contain at least one node".into());
        }
        if self.nodes.len() > 500 {
            return Err("Workflow exceeds the 500-node safety limit".into());
        }

        let mut ids = HashSet::new();
        for node in &self.nodes {
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
            block_type: "trigger".into(),
            title: id.into(),
            category: "trigger".into(),
            jac_node: None,
            config: json!({}),
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
            nodes: vec![node("a"), node("b")],
            edges: vec![edge("a-b", "a", "b")],
        };
        assert!(workflow.validate().is_ok());
    }

    #[test]
    fn rejects_cycles() {
        let workflow = WorkflowDocument {
            nodes: vec![node("a"), node("b")],
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
