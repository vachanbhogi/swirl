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
    // Legacy coordinates remain a serde concern at the native boundary. All
    // workflow validation and storage policy lives in Jac.
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

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
