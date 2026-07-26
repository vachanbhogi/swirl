"""
block_definitions.jac

This module defines the primary data structures, categories, and preset blocks
used by the Swirl workflow engine. It acts as the single source of truth for 
available block types, their inputs/outputs, and default configurations.
"""

import from typing { Optional, Any }

# ==============================================================================
# Object Definitions
# ==============================================================================

"""
BlockCategory represents a visual category for blocks in the UI toolbox.
"""
obj BlockCategory {
    has id: str;
    has name: str;
    has color: str;
    has bg: str;
    has border: str;
    has icon: str;
}

"""
BlockDefinition represents a single block type that can be instantiated
as a node in a workflow graph.
"""
obj BlockDefinition {
    has type: str;
    has category: str;
    has title: str;
    has subtitle: str;
    has description: str;
    has jac_node: str;
    has inputs: list[str];
    has outputs: list[str];
    has config: dict;
}

"""
WorkflowPreset represents a pre-configured workflow graph containing
starter nodes and edges to demonstrate common automation patterns.
"""
obj WorkflowPreset {
    has id: str;
    has name: str;
    has description: str;
    has nodes: list[dict];
    has edges: list[dict];
}

# ==============================================================================
# Category Data
# ==============================================================================

"""
Returns the list of all available block categories in the system.
"""
def BLOCK_CATEGORIES() -> list[BlockCategory] {
    return [
        BlockCategory(
            id="trigger", 
            name="Triggers", 
            color="#8B5CF6", 
            bg="rgba(139, 92, 246, 0.15)", 
            border="#A78BFA", 
            icon="Zap"
        ),
        BlockCategory(
            id="ai", 
            name="AI & LLM Transforms", 
            color="#F59E0B", 
            bg="rgba(245, 158, 11, 0.15)", 
            border="#FBBF24", 
            icon="Sparkles"
        ),
        BlockCategory(
            id="mac", 
            name="macOS Automation", 
            color="#06B6D4", 
            bg="rgba(6, 182, 212, 0.15)", 
            border="#67E8F9", 
            icon="Command"
        ),
        BlockCategory(
            id="mcp", 
            name="MCP Tools", 
            color="#10B981", 
            bg="rgba(16, 185, 129, 0.15)", 
            border="#34D399", 
            icon="Plug"
        ),
        BlockCategory(
            id="logic", 
            name="Control Logic", 
            color="#6366F1", 
            bg="rgba(99, 102, 241, 0.15)", 
            border="#818CF8", 
            icon="GitBranch"
        ),
        BlockCategory(
            id="output", 
            name="Outputs & Alerts", 
            color="#F43F5E", 
            bg="rgba(244, 63, 94, 0.15)", 
            border="#FB7185", 
            icon="Send"
        )
    ];
}

# ==============================================================================
# Block Library Data
# ==============================================================================

"""
Returns the definitive list of all block configurations available in the engine.
"""
def BLOCK_LIBRARY() -> list[BlockDefinition] {
    return [
        # --- Triggers ---
        BlockDefinition(
            type="trigger_email",
            category="trigger",
            title="On Email Received",
            subtitle="Apple Mail / Webhook Event",
            description="Triggers when a new high-priority email arrives",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["text", "sender", "subject"],
            config={"mailbox": "Inbox", "filterSubject": "Urgent", "checkIntervalSec": 15}
        ),
        BlockDefinition(
            type="trigger_cron",
            category="trigger",
            title="Cron Schedule",
            subtitle="Timed Event Walker",
            description="Triggers workflow on a recurring cron interval",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["timestamp"],
            config={"cron": "*/15 * * * *", "timezone": "America/Los_Angeles"}
        ),
        BlockDefinition(
            type="trigger_voice",
            category="trigger",
            title="Voice Command",
            subtitle="Microphone / Whisper Trigger",
            description="Triggers on custom spoken voice phrase",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["transcript", "confidence"],
            config={"wakeWord": "Hey Swirl", "language": "en-US", "listenTimeoutSec": 10}
        ),
        BlockDefinition(
            type="trigger_webhook",
            category="trigger",
            title="HTTP Webhook",
            subtitle="REST Endpoint Listener",
            description="Triggers when an incoming HTTP POST request is received",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["payload", "headers"],
            config={"path": "/api/v1/webhook", "method": "POST", "authRequired": False}
        ),
        BlockDefinition(
            type="trigger_clipboard",
            category="trigger",
            title="Clipboard Listener",
            subtitle="macOS Pasteboard Watcher",
            description="Triggers when new text or image is copied to clipboard",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["clipboardText", "contentType"],
            config={"watchText": True, "minChars": 5}
        ),
        BlockDefinition(
            type="trigger_file",
            category="trigger",
            title="On File Created",
            subtitle="Finder Watcher",
            description="Triggers when a file is added to a Mac folder",
            jac_node="TriggerBlock",
            inputs=[],
            outputs=["filePath", "fileName", "fileExt"],
            config={"watchPath": "~/Downloads", "filePattern": "*"}
        ),

        # --- AI Transforms ---
        BlockDefinition(
            type="llm_summarize",
            category="ai",
            title="LLM Summarizer",
            subtitle="Jac `by llm()` Walker",
            description="Summarize text & extract key points using Jac LLM capabilities",
            jac_node="LLMTransformBlock",
            inputs=["text"],
            outputs=["summary", "actionItems"],
            config={"prompt": "Summarize concisely and extract 3 bullet action items.", "maxTokens": 500, "temperature": 0.2}
        ),
        BlockDefinition(
            type="llm_extract",
            category="ai",
            title="LLM Entity Extractor",
            subtitle="Structured Data Extraction",
            description="Extract dates, names, prices, and JSON schemas from text",
            jac_node="LLMTransformBlock",
            inputs=["text"],
            outputs=["entities", "jsonData"],
            config={"extractSchema": "{\"names\": [], \"dates\": [], \"priority\": \"high|medium|low\"}"}
        ),
        BlockDefinition(
            type="llm_classifier",
            category="ai",
            title="LLM Intent Classifier",
            subtitle="Multi-Branch Classifier",
            description="Classify text into categories for downstream logic",
            jac_node="LLMTransformBlock",
            inputs=["text"],
            outputs=["category", "confidence"],
            config={"categories": ["Urgent Request", "Billing Inquiry", "General Feedback", "Spam"]}
        ),

        # --- macOS Automations ---
        BlockDefinition(
            type="mac_notes",
            category="mac",
            title="Apple Notes",
            subtitle="macOS AppleScript Bridge",
            description="Create a new note or append text to existing Apple Note",
            jac_node="MacAppBlock",
            inputs=["text", "title"],
            outputs=["noteId", "status"],
            config={"app": "Notes", "action": "create_note", "folder": "Swirl Automations", "defaultTitle": "Swirl Workflow Summary"}
        ),
        BlockDefinition(
            type="mac_finder",
            category="mac",
            title="Finder File Manager",
            subtitle="macOS File Operations",
            description="Organize files, create folders, move, or rename items",
            jac_node="MacAppBlock",
            inputs=["filePath"],
            outputs=["movedPath", "status"],
            config={"app": "Finder", "action": "organize_by_extension", "targetDirectory": "~/Desktop"}
        ),
        BlockDefinition(
            type="mac_notification",
            category="mac",
            title="Mac Notification",
            subtitle="System Notification Center",
            description="Post a native macOS banner notification alert",
            jac_node="MacAppBlock",
            inputs=["text", "title"],
            outputs=["status"],
            config={"app": "System", "action": "display_notification", "sound": "Glass"}
        ),
        BlockDefinition(
            type="mac_terminal",
            category="mac",
            title="Terminal Command",
            subtitle="Shell Script Walker",
            description="Run bash/zsh shell script or macOS CLI command",
            jac_node="MacAppBlock",
            inputs=["commandInput"],
            outputs=["stdout", "exitCode"],
            config={"app": "Terminal", "action": "exec_shell", "command": "echo \"Swirl execution completed at $(date)\""}
        ),

        # --- MCP Tools ---
        BlockDefinition(
            type="mcp_fetch",
            category="mcp",
            title="MCP Web Scraper",
            subtitle="Model Context Protocol",
            description="Fetch web page content via stdio/HTTP MCP Server",
            jac_node="MCPToolBlock",
            inputs=["url"],
            outputs=["markdownContent", "httpStatus"],
            config={"server": "fetch-mcp-server", "tool_name": "fetch_url", "timeoutMs": 10000}
        ),
        BlockDefinition(
            type="mcp_fs",
            category="mcp",
            title="MCP Filesystem",
            subtitle="Local MCP Tool Adapter",
            description="Safely read/write files via stdio MCP filesystem server",
            jac_node="MCPToolBlock",
            inputs=["path", "content"],
            outputs=["fileData", "status"],
            config={"server": "@modelcontextprotocol/server-filesystem", "tool_name": "read_file", "allowedDir": "/Users/mac/Documents"}
        ),
        BlockDefinition(
            type="mcp_search",
            category="mcp",
            title="MCP Web Search",
            subtitle="Brave / Google Search MCP",
            description="Perform real-time web queries using MCP search server",
            jac_node="MCPToolBlock",
            inputs=["query"],
            outputs=["searchResults", "sources"],
            config={"server": "brave-search-mcp", "tool_name": "brave_web_search", "maxResults": 5}
        ),

        # --- Logic Blocks ---
        BlockDefinition(
            type="logic_if",
            category="logic",
            title="If / Else Branch",
            subtitle="Conditional Control Flow",
            description="Branch walker execution based on boolean condition",
            jac_node="ConditionBlock",
            inputs=["value"],
            outputs=["truePath", "falsePath"],
            config={"operator": "contains", "matchString": "Urgent"}
        ),

        # --- Output Blocks ---
        BlockDefinition(
            type="output_slack",
            category="output",
            title="Slack Webhook",
            subtitle="Slack Channel Alert",
            description="Post formatted message payload to Slack incoming webhook",
            jac_node="OutputBlock",
            inputs=["text"],
            outputs=["response"],
            config={"webhookUrl": "https://hooks.slack.com/services/MOCK/SWIRL/KEY", "channel": "#automations"}
        )
    ];
}

# ==============================================================================
# Helper Methods
# ==============================================================================

"""
Retrieve a block definition by its type identifier.
"""
def get_block_by_type(block_type: str) -> BlockDefinition | None {
    for block in BLOCK_LIBRARY() {
        if block.type == block_type {
            return block;
        }
    }
    return None;
}

"""
Retrieve all block definitions belonging to a given category.
"""
def get_blocks_by_category(category: str) -> list[BlockDefinition] {
    return [block for block in BLOCK_LIBRARY() if block.category == category];
}

"""
Lookup the display color associated with a category identifier.
"""
def category_color(category_id: str) -> str {
    for cat in BLOCK_CATEGORIES() {
        if cat.id == category_id {
            return cat.color;
        }
    }
    # Fallback default color if category is not recognized
    return "#CBD5E1"; 
}

# ==============================================================================
# Starter & Preset Workflows
# ==============================================================================

"""
Returns the default starter workflow nodes and edges configuration.
"""
def default_starter_workflow() -> dict {
    return {
        "nodes": [
            {
                "id": "node-1", 
                "type": "trigger_email", 
                "title": "On Email Received", 
                "category": "trigger", 
                "x": 60, 
                "y": 120, 
                "config": {"mailbox": "Inbox", "filterSubject": "Urgent Action", "checkIntervalSec": 15}, 
                "status": "idle"
            },
            {
                "id": "node-2", 
                "type": "llm_summarize", 
                "title": "LLM Summarizer", 
                "category": "ai", 
                "x": 420, 
                "y": 120, 
                "config": {"prompt": "Summarize email and extract urgent action items for Jac agent.", "maxTokens": 300, "temperature": 0.2}, 
                "status": "idle"
            },
            {
                "id": "node-3", 
                "type": "mac_notes", 
                "title": "Apple Notes", 
                "category": "mac", 
                "x": 780, 
                "y": 60, 
                "config": {"app": "Notes", "action": "create_note", "folder": "Swirl Action Items", "defaultTitle": "Urgent Mail Brief"}, 
                "status": "idle"
            },
            {
                "id": "node-4", 
                "type": "mac_notification", 
                "title": "Mac Notification", 
                "category": "mac", 
                "x": 780, 
                "y": 260, 
                "config": {"app": "System", "action": "display_notification", "sound": "Glass"}, 
                "status": "idle"
            }
        ],
        "edges": [
            {"id": "edge-1-2", "source": "node-1", "target": "node-2", "sourcePort": "text", "targetPort": "text"},
            {"id": "edge-2-3", "source": "node-2", "target": "node-3", "sourcePort": "summary", "targetPort": "text"},
            {"id": "edge-2-4", "source": "node-2", "target": "node-4", "sourcePort": "actionItems", "targetPort": "text"}
        ]
    };
}

"""
Returns a curated list of workflow presets available for users to instantiate.
"""
def workflow_presets() -> list[WorkflowPreset] {
    starter = default_starter_workflow();
    
    return [
        WorkflowPreset(
            id="email_notes",
            name="📥 Email Summarizer & Apple Notes",
            description="Monitors incoming emails, runs LLM summary walker, saves note and notifies Mac desktop.",
            nodes=starter["nodes"],
            edges=starter["edges"]
        ),
        WorkflowPreset(
            id="desktop_cleaner",
            name="📁 Desktop Organizer & Slack Alert",
            description="Monitors ~/Desktop folder, categorizes files by extension using Finder block, sends Slack summary.",
            nodes=[
                {
                    "id": "node-d1", 
                    "type": "trigger_file", 
                    "title": "On File Created", 
                    "category": "trigger", 
                    "x": 60, 
                    "y": 140, 
                    "config": {"watchPath": "~/Desktop", "filePattern": "*"}, 
                    "status": "idle"
                },
                {
                    "id": "node-d2", 
                    "type": "mac_finder", 
                    "title": "Finder File Manager", 
                    "category": "mac", 
                    "x": 420, 
                    "y": 140, 
                    "config": {"app": "Finder", "action": "organize_by_extension", "targetDirectory": "~/Desktop"}, 
                    "status": "idle"
                },
                {
                    "id": "node-d3", 
                    "type": "output_slack", 
                    "title": "Slack Webhook", 
                    "category": "output", 
                    "x": 780, 
                    "y": 140, 
                    "config": {"channel": "#desktop-bot", "webhookUrl": "https://hooks.slack.com/..."}, 
                    "status": "idle"
                }
            ],
            edges=[
                {"id": "edge-d1-d2", "source": "node-d1", "target": "node-d2", "sourcePort": "filePath", "targetPort": "filePath"},
                {"id": "edge-d2-d3", "source": "node-d2", "target": "node-d3", "sourcePort": "movedPath", "targetPort": "text"}
            ]
        ),
        WorkflowPreset(
            id="mcp_scraper",
            name="🌐 MCP Web Scraper & AI Digest",
            description="Uses stdio MCP web fetcher tool, feeds markdown into Jac LLM walker, creates Apple Note.",
            nodes=[
                {
                    "id": "node-m1", 
                    "type": "trigger_cron", 
                    "title": "Cron Schedule", 
                    "category": "trigger", 
                    "x": 60, 
                    "y": 140, 
                    "config": {"cron": "0 9 * * *", "timezone": "America/Los_Angeles"}, 
                    "status": "idle"
                },
                {
                    "id": "node-m2", 
                    "type": "mcp_fetch", 
                    "title": "MCP Web Scraper", 
                    "category": "mcp", 
                    "x": 420, 
                    "y": 140, 
                    "config": {"server": "fetch-mcp-server", "tool_name": "fetch_url"}, 
                    "status": "idle"
                },
                {
                    "id": "node-m3", 
                    "type": "llm_summarize", 
                    "title": "LLM Summarizer", 
                    "category": "ai", 
                    "x": 780, 
                    "y": 140, 
                    "config": {"prompt": "Extract key news headlines and bullet points.", "maxTokens": 400}, 
                    "status": "idle"
                },
                {
                    "id": "node-m4", 
                    "type": "mac_notes", 
                    "title": "Apple Notes", 
                    "category": "mac", 
                    "x": 1140, 
                    "y": 140, 
                    "config": {"app": "Notes", "action": "create_note", "folder": "Daily Digests"}, 
                    "status": "idle"
                }
            ],
            edges=[
                {"id": "edge-m1-m2", "source": "node-m1", "target": "node-m2", "sourcePort": "timestamp", "targetPort": "url"},
                {"id": "edge-m2-m3", "source": "node-m2", "target": "node-m3", "sourcePort": "markdownContent", "targetPort": "text"},
                {"id": "edge-m3-m4", "source": "node-m3", "target": "node-m4", "sourcePort": "summary", "targetPort": "text"}
            ]
        )
    ];
}
