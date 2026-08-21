use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

fn default_input_type() -> String {
    "string".into()
}

fn default_automation_mode() -> String {
    "accessibility".into()
}

fn default_risk() -> String {
    "medium".into()
}

fn default_test_status() -> String {
    "untested".into()
}

/// A stable reference embedded in a workflow. The fingerprint binds the node
/// to the exact immutable tool snapshot it was reviewed against.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedToolRef {
    pub id: String,
    pub version: u64,
    pub fingerprint: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedToolTarget {
    pub application_name: String,
    pub bundle_id: String,
    pub process_name: String,
    #[serde(default)]
    pub observed_version: String,
    #[serde(default = "default_automation_mode")]
    pub automation_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedToolInput {
    pub key: String,
    pub label: String,
    #[serde(default = "default_input_type")]
    pub input_type: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub default_value: String,
    #[serde(default)]
    pub sensitive: bool,
    #[serde(default)]
    pub description: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AccessibilitySelector {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub identifier: Option<String>,
}

/// The only operations accepted from AI generation. There is intentionally no
/// raw-script, shell, coordinate, application-name, or dynamic-eval variant.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum AutomationStep {
    ActivateApp,
    Wait {
        seconds: f64,
    },
    WaitFrontmost {
        #[serde(rename = "timeoutSec", alias = "timeout_sec")]
        #[serde(default = "default_timeout_sec")]
        timeout_sec: f64,
    },
    KeyChord {
        keys: Vec<String>,
    },
    PressKey {
        key: String,
    },
    TypeInput {
        #[serde(rename = "inputKey", alias = "input_key")]
        input_key: String,
    },
    WaitElement {
        selector: AccessibilitySelector,
        #[serde(rename = "timeoutSec", alias = "timeout_sec")]
        #[serde(default = "default_timeout_sec")]
        timeout_sec: f64,
    },
    ClickElement {
        selector: AccessibilitySelector,
    },
    ReadElement {
        selector: AccessibilitySelector,
        #[serde(rename = "outputKey", alias = "output_key")]
        #[serde(default)]
        output_key: String,
    },
}

fn default_timeout_sec() -> f64 {
    5.0
}

impl AutomationStep {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ActivateApp => "activate_app",
            Self::Wait { .. } => "wait",
            Self::WaitFrontmost { .. } => "wait_frontmost",
            Self::KeyChord { .. } => "key_chord",
            Self::PressKey { .. } => "press_key",
            Self::TypeInput { .. } => "type_input",
            Self::WaitElement { .. } => "wait_element",
            Self::ClickElement { .. } => "click_element",
            Self::ReadElement { .. } => "read_element",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedToolEffect {
    #[serde(rename = "type")]
    pub effect_type: String,
    pub description: String,
    #[serde(default)]
    pub requires_approval: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ToolValidation {
    #[serde(default)]
    pub valid: bool,
    #[serde(default)]
    pub status: String,
    #[serde(default, alias = "issues")]
    pub messages: Vec<String>,
}

impl Default for ToolValidation {
    fn default() -> Self {
        Self {
            valid: false,
            status: "pending".into(),
            messages: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedAppToolDraft {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub source_prompt: String,
    pub application_query: String,
    #[serde(default)]
    pub inputs: Vec<GeneratedToolInput>,
    #[serde(default)]
    pub program: Vec<AutomationStep>,
    #[serde(default)]
    pub effects: Vec<GeneratedToolEffect>,
    #[serde(default, alias = "requiredPermissions")]
    pub permissions: Vec<String>,
    #[serde(default = "default_risk")]
    pub risk: String,
    #[serde(default)]
    pub validation: ToolValidation,
    #[serde(default = "default_test_status")]
    pub test_status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedToolSnapshot {
    pub target: GeneratedToolTarget,
    #[serde(default)]
    pub inputs: Vec<GeneratedToolInput>,
    #[serde(default)]
    pub program: Vec<AutomationStep>,
    #[serde(default)]
    pub effects: Vec<GeneratedToolEffect>,
    #[serde(default)]
    pub permissions: Vec<String>,
    #[serde(default = "default_risk")]
    pub risk: String,
    #[serde(default)]
    pub validation: ToolValidation,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
#[allow(dead_code)] // Public persisted schema; workflow config remains a flexible Value boundary.
pub enum ToolBinding {
    Literal { value: String },
    Context { path: String },
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)] // Kept typed for external/schema consumers even though execution accepts Value.
pub struct GeneratedToolNodeConfig {
    #[serde(default)]
    pub bindings: HashMap<String, ToolBinding>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedAppToolVersion {
    pub id: String,
    pub version: u64,
    pub fingerprint: String,
    pub name: String,
    pub description: String,
    pub source_prompt: String,
    pub target: GeneratedToolTarget,
    #[serde(default)]
    pub inputs: Vec<GeneratedToolInput>,
    #[serde(default)]
    pub program: Vec<AutomationStep>,
    #[serde(default)]
    pub effects: Vec<GeneratedToolEffect>,
    #[serde(default)]
    pub permissions: Vec<String>,
    #[serde(default = "default_risk")]
    pub risk: String,
    #[serde(default)]
    pub validation: ToolValidation,
    #[serde(default = "default_test_status")]
    pub test_status: String,
    #[serde(default)]
    pub created_at: u64,
}

impl GeneratedAppToolVersion {
    pub fn tool_ref(&self) -> GeneratedToolRef {
        GeneratedToolRef {
            id: self.id.clone(),
            version: self.version,
            fingerprint: self.fingerprint.clone(),
        }
    }

    pub fn snapshot(&self) -> GeneratedToolSnapshot {
        GeneratedToolSnapshot {
            target: self.target.clone(),
            inputs: self.inputs.clone(),
            program: self.program.clone(),
            effects: self.effects.clone(),
            permissions: self.permissions.clone(),
            risk: self.risk.clone(),
            validation: self.validation.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedAppToolRecord {
    pub id: String,
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub latest_version: u64,
    #[serde(default)]
    pub published_version: u64,
    #[serde(default)]
    pub archived: bool,
    #[serde(default)]
    pub created_at: u64,
    #[serde(default)]
    pub updated_at: u64,
    #[serde(default)]
    pub versions: Vec<GeneratedAppToolVersion>,
}

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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_ref: Option<GeneratedToolRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_snapshot: Option<GeneratedToolSnapshot>,
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

    #[test]
    fn generated_tool_nodes_round_trip_pinned_snapshot_and_camel_case_program() {
        let mut workflow: WorkflowDocument = serde_json::from_value(json!({
            "nodes": [{
                "id": "discord-tool", "type": "generated_app_tool",
                "title": "Send Discord DM", "category": "mac",
                "toolRef": {"id": "send-discord-dm", "version": 1, "fingerprint": "a".repeat(64)},
                "toolSnapshot": {
                    "target": {
                        "applicationName": "Discord", "bundleId": "com.hnc.Discord",
                        "processName": "Discord", "observedVersion": "1",
                        "automationMode": "accessibility"
                    },
                    "inputs": [{
                        "key": "message", "label": "Message", "inputType": "string",
                        "required": true, "defaultValue": "", "sensitive": true
                    }],
                    "program": [
                        {"op": "activate_app"},
                        {"op": "wait_frontmost", "timeoutSec": 5},
                        {"op": "type_input", "inputKey": "message"}
                    ],
                    "effects": [{"type": "send_message", "description": "Sends a message", "requiresApproval": true}],
                    "permissions": ["Accessibility"], "risk": "high",
                    "validation": {"valid": true, "status": "validated", "issues": []}
                },
                "config": {"bindings": {"message": {"kind": "context", "path": "text"}}},
                "position": {"x": 260, "y": 200}
            }],
            "edges": []
        }))
        .unwrap();

        workflow.migrate_legacy_layout();
        let serialized = serde_json::to_value(workflow).unwrap();
        let node = &serialized["nodes"][0];
        assert_eq!(node["toolRef"]["version"], 1);
        assert_eq!(node["toolSnapshot"]["program"][1]["timeoutSec"], 5.0);
        assert_eq!(node["toolSnapshot"]["program"][2]["inputKey"], "message");
        assert_eq!(node["config"]["bindings"]["message"]["path"], "text");
        assert_eq!(node["position"]["x"], 260.0);
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
