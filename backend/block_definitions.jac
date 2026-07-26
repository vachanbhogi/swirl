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
        # --- macOS Automations ---
        BlockDefinition(
            type="mac_wait_email",
            category="mac",
            title="Wait for Email",
            subtitle="Apple Mail Message Wait",
            description="Wait for a new Apple Mail message after the workflow starts",
            jac_node="MacAppBlock",
            inputs=[],
            outputs=["text", "sender", "subject"],
            config={"app": "Mail", "action": "wait_for_new_message", "mailbox": "Inbox", "filterSubject": "", "checkIntervalSec": 15, "waitTimeoutSec": 0}
        ),
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
            config={"server": "fetch-mcp-server", "tool_name": "fetch", "url": "https://example.com", "timeoutMs": 10000}
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
            config={"server": "filesystem", "tool_name": "read_text_file", "path": "$SWIRL_DOCUMENTS", "allowedDir": "$SWIRL_DOCUMENTS"}
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
            config={"server": "brave-search-mcp", "tool_name": "brave_web_search", "query": "", "maxResults": 5}
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
                "id": "workflow-on-run",
                "type": "on_run",
                "title": "On Run",
                "category": "source",
                "x": 60, 
                "y": 120, 
                "config": {},
                "status": "idle"
            },
        ],
        "edges": []
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
        )
    ];
}
