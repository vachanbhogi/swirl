/**
 * Swirl Block Definitions & Jaclang Code Generator
 * Scratch-style visual blocks matching Jac Node & Walker primitives (PRD & AGENTS.md compliant)
 */

export const BLOCK_CATEGORIES = [
  { id: 'source', name: 'Workflow Source', color: '#F97316', bg: 'rgba(249, 115, 22, 0.15)', border: '#FB923C', icon: 'Radio' },
  { id: 'ai', name: 'AI & LLM Transforms', color: '#F59E0B', bg: 'rgba(245, 158, 11, 0.15)', border: '#FBBF24', icon: 'Sparkles' },
  { id: 'mac', name: 'macOS Automation', color: '#06B6D4', bg: 'rgba(6, 182, 212, 0.15)', border: '#67E8F9', icon: 'Command' },
  { id: 'mcp', name: 'MCP Tools', color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)', border: '#34D399', icon: 'Plug' },
  { id: 'output', name: 'Outputs & Alerts', color: '#F43F5E', bg: 'rgba(244, 63, 94, 0.15)', border: '#FB7185', icon: 'Send' }
];

export const BLOCK_LIBRARY = [
  // AI & LLM Transforms
  {
    type: 'llm_summarize',
    category: 'ai',
    title: 'LLM Summarizer',
    subtitle: 'Jac `by llm()` Walker',
    description: 'Summarize text & extract key points using Jac LLM capabilities',
    jacNode: 'LLMTransformBlock',
    inputs: ['text'],
    outputs: ['summary', 'actionItems'],
    config: {
      prompt: 'Summarize concisely and extract 3 bullet action items.',
      maxTokens: 500,
      temperature: 0.2
    }
  },
  // macOS Automation
  {
    type: 'mac_wait_email',
    category: 'mac',
    title: 'Wait for Email',
    subtitle: 'Apple Mail Message Wait',
    description: 'Wait for a new Apple Mail message after the workflow starts',
    jacNode: 'MacAppBlock',
    inputs: [],
    outputs: ['text', 'sender', 'subject'],
    config: { app: 'Mail', action: 'wait_for_new_message', mailbox: 'Inbox', filterSubject: '', checkIntervalSec: 15, waitTimeoutSec: 0 }
  },
  {
    type: 'mac_notes',
    category: 'mac',
    title: 'Apple Notes',
    subtitle: 'macOS AppleScript Bridge',
    description: 'Create a new note or append text to existing Apple Note',
    jacNode: 'MacAppBlock',
    inputs: ['text', 'title'],
    outputs: ['noteId', 'status'],
    config: {
      app: 'Notes',
      action: 'create_note',
      folder: 'Swirl Automations',
      defaultTitle: 'Swirl Workflow Summary'
    }
  },
  {
    type: 'mac_finder',
    category: 'mac',
    title: 'Finder File Manager',
    subtitle: 'macOS File Operations',
    description: 'Organize files, create folders, move, or rename items',
    jacNode: 'MacAppBlock',
    inputs: ['filePath'],
    outputs: ['movedPath', 'status'],
    config: {
      app: 'Finder',
      action: 'organize_by_extension',
      targetDirectory: '~/Desktop'
    }
  },
  {
    type: 'mac_notification',
    category: 'mac',
    title: 'Mac Notification',
    subtitle: 'System Notification Center',
    description: 'Post a native macOS banner notification alert',
    jacNode: 'MacAppBlock',
    inputs: ['text', 'title'],
    outputs: ['status'],
    config: {
      app: 'System',
      action: 'display_notification',
      sound: 'Glass'
    }
  },
  {
    type: 'mac_terminal',
    category: 'mac',
    title: 'Terminal Command',
    subtitle: 'Shell Script Walker',
    description: 'Run bash/zsh shell script or macOS CLI command',
    jacNode: 'MacAppBlock',
    inputs: ['commandInput'],
    outputs: ['stdout', 'exitCode'],
    config: {
      app: 'Terminal',
      action: 'exec_shell',
      command: 'echo "Swirl execution completed at $(date)"'
    }
  },

  // MCP Tools
  {
    type: 'mcp_fetch',
    category: 'mcp',
    title: 'MCP Web Scraper',
    subtitle: 'Model Context Protocol',
    description: 'Fetch web page content via stdio/HTTP MCP Server',
    jacNode: 'MCPToolBlock',
    inputs: ['url'],
    outputs: ['markdownContent', 'httpStatus'],
    config: {
      server: 'fetch-mcp-server',
      tool_name: 'fetch',
      url: 'https://example.com',
      timeoutMs: 10000
    }
  },
  {
    type: 'mcp_fs',
    category: 'mcp',
    title: 'MCP Filesystem',
    subtitle: 'Local MCP Tool Adapter',
    description: 'Safely read/write files via stdio MCP filesystem server',
    jacNode: 'MCPToolBlock',
    inputs: ['path', 'content'],
    outputs: ['fileData', 'status'],
    config: {
      server: 'filesystem',
      tool_name: 'read_text_file',
      path: '$SWIRL_DOCUMENTS',
      allowedDir: '$SWIRL_DOCUMENTS'
    }
  },
  {
    type: 'mcp_search',
    category: 'mcp',
    title: 'MCP Web Search',
    subtitle: 'Brave / Google Search MCP',
    description: 'Perform real-time web queries using MCP search server',
    jacNode: 'MCPToolBlock',
    inputs: ['query'],
    outputs: ['searchResults', 'sources'],
    config: {
      server: 'brave-search-mcp',
      tool_name: 'brave_web_search',
      query: '',
      maxResults: 5
    }
  },

  // Outputs
  {
    type: 'output_slack',
    category: 'output',
    title: 'Slack Webhook',
    subtitle: 'Slack Channel Alert',
    description: 'Post formatted message payload to Slack incoming webhook',
    jacNode: 'OutputBlock',
    inputs: ['text'],
    outputs: ['response'],
    config: {
      webhookUrl: 'https://hooks.slack.com/services/MOCK/SWIRL/KEY',
      channel: '#automations'
    }
  }
];

// Initial Starter Workflow
export const INITIAL_NODES = [
  {
    id: 'workflow-on-run',
    type: 'on_run',
    title: 'On Run',
    category: 'source',
    jacNode: 'SourceBlock',
    x: 60,
    y: 120,
    config: {},
    status: 'idle'
  },
];

export const INITIAL_EDGES = [];

// Workflow Presets
export const WORKFLOW_PRESETS = [
  {
    id: 'email_notes',
    name: '📥 Email Summarizer & Apple Notes',
    description: 'Monitors incoming emails, runs LLM summary walker, saves note and notifies Mac desktop.',
    nodes: INITIAL_NODES,
    edges: INITIAL_EDGES
  }
];

/**
 * Real-Time Jaclang Code Emitter
 * Converts visual block graph into idiomatic .jac source code matching Swirl AGENTS.md specs
 */
export function generateJacCode(nodes, edges) {
  if (!nodes || nodes.length === 0) {
    return `# Swirl Jaclang Source Code Emitter
# Visual canvas is empty. Drag blocks to generate Jac code.
`;
  }

  let code = `# =========================================================
# Swirl — Generated Jaclang Source
# Project: Swirl (JacHacks SF 2026)
# Compiler target: Jaclang v0.7.8
# Nodes: ${nodes.length} | Connections: ${edges.length}
# =========================================================

import:py os;
import:py sys;
import:py json;

# ---------------------------------------------------------
# Base Node & Specialized Jac Block Declarations
# ---------------------------------------------------------

node WorkflowBlock {
    has id: str;
    has block_type: str;
    has title: str;
    has config: dict;
    has status: str = "idle";
    has output: dict = {};

    can execute(ctx: dict) -> dict {
        print(f"[WorkflowBlock] Executing base node: {self.title}");
        return ctx;
    }
}

node SourceBlock :WorkflowBlock: {
    can execute(ctx: dict) -> dict {
        print(f"⚡ [SourceBlock] Manual workflow run: {self.title}");
        self.status = "success";
        ctx["triggerType"] = "manual";
        return ctx;
    }
}

node LLMTransformBlock :WorkflowBlock: {
    # Jaclang Native LLM capability declaration
    can summarize_text(input_text: str, instruction: str) -> str by llm();

    can execute(ctx: dict) -> dict {
        self.status = "running";
        print(f"🧠 [LLMTransformBlock] Invoking Jac 'by llm()' walker for: {self.title}");
        input_text = ctx.get("text", self.config.get("prompt", "Default prompt"));
        instruction = self.config.get("prompt", "Summarize concisely");
        
        # Simulating Jac LLM transformation
        result = f"Summary of input: {input_text[:60]}... [Action Required]";
        self.output = {"summary": result, "status": "ok"};
        self.status = "success";
        ctx["text"] = result;
        return ctx;
    }
}

node MacAppBlock :WorkflowBlock: {
    can execute(ctx: dict) -> dict {
        self.status = "running";
        app_name = self.config.get("app", "Notes");
        action = self.config.get("action", "create_note");
        content = ctx.get("text", "Default Swirl Content");
        print(f"💻 [MacAppBlock] Dispatching macOS AppleScript -> App: {app_name}, Action: {action}");
        
        self.output = {"app": app_name, "action": action, "status": "executed"};
        self.status = "success";
        return ctx;
    }
}

node MCPToolBlock :WorkflowBlock: {
    can execute(ctx: dict) -> dict {
        self.status = "running";
        server_name = self.config.get("server", "stdio-local");
        tool_name = self.config.get("tool_name", "fetch");
        print(f"🔌 [MCPToolBlock] JSON-RPC Tool Call -> Server: {server_name}, Tool: {tool_name}");
        
        self.output = {"mcp_status": 200, "tool": tool_name, "result": "MCP Tool executed successfully"};
        self.status = "success";
        return ctx;
    }
}

node OutputBlock :WorkflowBlock: {
    can execute(ctx: dict) -> dict {
        print(f"🏁 [OutputBlock] Sending final workflow alert: {self.title}");
        self.status = "success";
        return ctx;
    }
}

# ---------------------------------------------------------
# Swirl Visual Graph Initialization & Node Instances
# ---------------------------------------------------------

with entry {
    print("🕸️ [Jac Graph Init] Instantiating visual workflow nodes...");
`;

  // Emit node instances
  nodes.forEach((n, idx) => {
    const varName = `node_${n.id.replace(/-/g, '_')}`;
    let blockClass = 'WorkflowBlock';
    if (n.category === 'source') blockClass = 'SourceBlock';
    else if (n.category === 'ai') blockClass = 'LLMTransformBlock';
    else if (n.category === 'mac') blockClass = 'MacAppBlock';
    else if (n.category === 'mcp') blockClass = 'MCPToolBlock';
    else if (n.category === 'output') blockClass = 'OutputBlock';

    const configJson = JSON.stringify(n.config || {});
    code += `    ${varName} = spawn node::${blockClass}(
        id="${n.id}",
        block_type="${n.type}",
        title="${n.title.replace(/"/g, '\\"')}",
        custom_prompt="${(n.customPrompt || '').replace(/"/g, '\\"')}",
        config=${configJson}
    );\n`;
  });

  code += `\n    # Connect Edges\n`;

  // Emit edge connections
  if (edges.length > 0) {
    edges.forEach(e => {
      const srcVar = `node_${e.source.replace(/-/g, '_')}`;
      const tgtVar = `node_${e.target.replace(/-/g, '_')}`;
      code += `    ${srcVar} ++> ${tgtVar};\n`;
    });
  } else {
    // Chain sequentially if no edges
    for (let i = 0; i < nodes.length - 1; i++) {
      const srcVar = `node_${nodes[i].id.replace(/-/g, '_')}`;
      const tgtVar = `node_${nodes[i + 1].id.replace(/-/g, '_')}`;
      code += `    ${srcVar} ++> ${tgtVar};\n`;
    }
  }

  // Emit Walker definition
  code += `
}

# ---------------------------------------------------------
# Main Jac Graph Traversal Agent Walker
# ---------------------------------------------------------

walker WorkflowExecutorWalker {
    has ctx: dict = {};
    has logs: list = [];

    with entry {
        print("🚀 [WorkflowExecutorWalker] Starting Jac Walker graph traversal...");
        # Traverses from root trigger through visual directed edges
        visit [--sn:WorkflowBlock-->];
    }
}
`;

  return code;
}
