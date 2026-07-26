/**
 * Swirl Block Definitions & Jaclang Code Generator
 * Scratch-style visual blocks matching Jac Node & Walker primitives (PRD & AGENTS.md compliant)
 */

export const BLOCK_CATEGORIES = [
  { id: 'source', name: 'Workflow Source', color: '#F97316', bg: 'rgba(249, 115, 22, 0.15)', border: '#FB923C', icon: 'Radio' },
  { id: 'trigger', name: 'Triggers', color: '#8B5CF6', bg: 'rgba(139, 92, 246, 0.15)', border: '#A78BFA', icon: 'Zap' },
  { id: 'ai', name: 'AI & LLM Transforms', color: '#F59E0B', bg: 'rgba(245, 158, 11, 0.15)', border: '#FBBF24', icon: 'Sparkles' },
  { id: 'mac', name: 'macOS Automation', color: '#06B6D4', bg: 'rgba(6, 182, 212, 0.15)', border: '#67E8F9', icon: 'Command' },
  { id: 'mcp', name: 'MCP Tools', color: '#10B981', bg: 'rgba(16, 185, 129, 0.15)', border: '#34D399', icon: 'Plug' },
  { id: 'logic', name: 'Control Logic', color: '#6366F1', bg: 'rgba(99, 102, 241, 0.15)', border: '#818CF8', icon: 'GitBranch' },
  { id: 'output', name: 'Outputs & Alerts', color: '#F43F5E', bg: 'rgba(244, 63, 94, 0.15)', border: '#FB7185', icon: 'Send' }
];

export const BLOCK_LIBRARY = [
  // Source is mandatory and is rendered by the canvas; it is not draggable.
  // Triggers
  {
    type: 'trigger_email',
    category: 'trigger',
    title: 'On Email Received',
    subtitle: 'Apple Mail / Webhook Event',
    description: 'Triggers when any new email arrives',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['text', 'sender', 'subject'],
    config: {
      mailbox: 'Inbox',
      filterSubject: '',
      checkIntervalSec: 15
    }
  },
  {
    type: 'trigger_cron',
    category: 'trigger',
    title: 'Cron Schedule',
    subtitle: 'Timed Event Walker',
    description: 'Triggers workflow on a recurring cron interval',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['timestamp'],
    config: {
      cron: '*/15 * * * *',
      timezone: 'America/Los_Angeles'
    }
  },
  {
    type: 'trigger_voice',
    category: 'trigger',
    title: 'Voice Command',
    subtitle: 'Microphone / Whisper Trigger',
    description: 'Triggers on custom spoken voice phrase',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['transcript', 'confidence'],
    config: {
      wakeWord: 'Hey Swirl',
      language: 'en-US',
      listenTimeoutSec: 10
    }
  },
  {
    type: 'trigger_webhook',
    category: 'trigger',
    title: 'HTTP Webhook',
    subtitle: 'REST Endpoint Listener',
    description: 'Triggers when an incoming HTTP POST request is received',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['payload', 'headers'],
    config: {
      path: '/api/v1/webhook',
      method: 'POST',
      authRequired: false
    }
  },
  {
    type: 'trigger_clipboard',
    category: 'trigger',
    title: 'Clipboard Listener',
    subtitle: 'macOS Pasteboard Watcher',
    description: 'Triggers when new text or image is copied to clipboard',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['clipboardText', 'contentType'],
    config: {
      watchText: true,
      minChars: 5
    }
  },
  {
    type: 'trigger_file',
    category: 'trigger',
    title: 'On File Created',
    subtitle: 'Finder Watcher',
    description: 'Triggers when a file is added to a Mac folder',
    jacNode: 'TriggerBlock',
    inputs: [],
    outputs: ['filePath', 'fileName', 'fileExt'],
    config: {
      watchPath: '~/Downloads',
      filePattern: '*'
    }
  },

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
  {
    type: 'llm_extract',
    category: 'ai',
    title: 'LLM Entity Extractor',
    subtitle: 'Structured Data Extraction',
    description: 'Extract dates, names, prices, and JSON schemas from text',
    jacNode: 'LLMTransformBlock',
    inputs: ['text'],
    outputs: ['entities', 'jsonData'],
    config: {
      extractSchema: '{"names": [], "dates": [], "priority": "high|medium|low"}'
    }
  },
  {
    type: 'llm_classifier',
    category: 'ai',
    title: 'LLM Intent Classifier',
    subtitle: 'Multi-Branch Classifier',
    description: 'Classify text into categories for downstream logic',
    jacNode: 'LLMTransformBlock',
    inputs: ['text'],
    outputs: ['category', 'confidence'],
    config: {
      categories: ['Urgent Request', 'Billing Inquiry', 'General Feedback', 'Spam']
    }
  },

  // macOS Automation
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

  // Control Logic
  {
    type: 'logic_if',
    category: 'logic',
    title: 'If / Else Branch',
    subtitle: 'Conditional Control Flow',
    description: 'Branch walker execution based on boolean condition',
    jacNode: 'ConditionBlock',
    inputs: ['value'],
    outputs: ['truePath', 'falsePath'],
    config: {
      operator: 'contains',
      matchString: 'Urgent'
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
    id: 'workflow-source',
    type: 'source',
    title: 'Source',
    category: 'source',
    jacNode: 'SourceBlock',
    x: 60,
    y: 120,
    config: {
      eventType: 'trigger_email',
      mailbox: 'Inbox',
      filterSubject: '',
      checkIntervalSec: 15,
      waitTimeoutSec: 0
    },
    status: 'idle'
  },
  {
    id: 'node-2',
    type: 'llm_summarize',
    title: 'LLM Summarizer',
    category: 'ai',
    x: 420,
    y: 120,
    config: {
      prompt: 'Summarize this email and list any action items.',
      maxTokens: 300,
      temperature: 0.2
    },
    status: 'idle'
  },
  {
    id: 'node-3',
    type: 'mac_notes',
    title: 'Apple Notes',
    category: 'mac',
    x: 780,
    y: 60,
    config: {
      app: 'Notes',
      action: 'create_note',
      folder: 'Swirl Action Items',
      defaultTitle: 'Email Summary'
    },
    status: 'idle'
  },
  {
    id: 'node-4',
    type: 'mac_notification',
    title: 'Mac Notification',
    category: 'mac',
    x: 780,
    y: 260,
    config: {
      app: 'System',
      action: 'display_notification',
      sound: 'Glass'
    },
    status: 'idle'
  }
];

export const INITIAL_EDGES = [
  { id: 'edge-1-2', source: 'workflow-source', target: 'node-2', sourcePort: 'event', targetPort: 'text' },
  { id: 'edge-2-3', source: 'node-2', target: 'node-3', sourcePort: 'summary', targetPort: 'text' },
  { id: 'edge-2-4', source: 'node-2', target: 'node-4', sourcePort: 'actionItems', targetPort: 'text' }
];

// Workflow Presets
export const WORKFLOW_PRESETS = [
  {
    id: 'email_notes',
    name: '📥 Email Summarizer & Apple Notes',
    description: 'Monitors incoming emails, runs LLM summary walker, saves note and notifies Mac desktop.',
    nodes: INITIAL_NODES,
    edges: INITIAL_EDGES
  },
  {
    id: 'desktop_cleaner',
    name: '📁 Desktop Organizer & Slack Alert',
    description: 'Monitors ~/Desktop folder, categorizes files by extension using Finder block, sends Slack summary.',
    nodes: [
      {
        id: 'node-d1',
        type: 'trigger_file',
        title: 'On File Created',
        category: 'trigger',
        x: 60,
        y: 140,
        config: { watchPath: '~/Desktop', filePattern: '*' },
        status: 'idle'
      },
      {
        id: 'node-d2',
        type: 'mac_finder',
        title: 'Finder File Manager',
        category: 'mac',
        x: 420,
        y: 140,
        config: { app: 'Finder', action: 'organize_by_extension', targetDirectory: '~/Desktop' },
        status: 'idle'
      },
      {
        id: 'node-d3',
        type: 'output_slack',
        title: 'Slack Webhook',
        category: 'output',
        x: 780,
        y: 140,
        config: { channel: '#desktop-bot', webhookUrl: 'https://hooks.slack.com/...' },
        status: 'idle'
      }
    ],
    edges: [
      { id: 'edge-d1-d2', source: 'node-d1', target: 'node-d2', sourcePort: 'filePath', targetPort: 'filePath' },
      { id: 'edge-d2-d3', source: 'node-d2', target: 'node-d3', sourcePort: 'movedPath', targetPort: 'text' }
    ]
  },
  {
    id: 'mcp_scraper',
    name: '🌐 MCP Web Scraper & AI Digest',
    description: 'Uses stdio MCP web fetcher tool, feeds markdown into Jac LLM walker, creates Apple Note.',
    nodes: [
      {
        id: 'node-m1',
        type: 'trigger_cron',
        title: 'Cron Schedule',
        category: 'trigger',
        x: 60,
        y: 140,
        config: { cron: '0 9 * * *', timezone: 'America/Los_Angeles' },
        status: 'idle'
      },
      {
        id: 'node-m2',
        type: 'mcp_fetch',
        title: 'MCP Web Scraper',
        category: 'mcp',
        x: 420,
        y: 140,
        config: { server: 'fetch-mcp-server', tool_name: 'fetch', url: 'https://example.com' },
        status: 'idle'
      },
      {
        id: 'node-m3',
        type: 'llm_summarize',
        title: 'LLM Summarizer',
        category: 'ai',
        x: 780,
        y: 140,
        config: { prompt: 'Extract key news headlines and bullet points.', maxTokens: 400 },
        status: 'idle'
      },
      {
        id: 'node-m4',
        type: 'mac_notes',
        title: 'Apple Notes',
        category: 'mac',
        x: 1140,
        y: 140,
        config: { app: 'Notes', action: 'create_note', folder: 'Daily Digests' },
        status: 'idle'
      }
    ],
    edges: [
      { id: 'edge-m1-m2', source: 'node-m1', target: 'node-m2', sourcePort: 'timestamp', targetPort: 'url' },
      { id: 'edge-m2-m3', source: 'node-m2', target: 'node-m3', sourcePort: 'markdownContent', targetPort: 'text' },
      { id: 'edge-m3-m4', source: 'node-m3', target: 'node-m4', sourcePort: 'summary', targetPort: 'text' }
    ]
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
# Swirl AI Visual Scratch Editor — Generated Jaclang Source
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
        print(f"⚡ [SourceBlock] Triggered source event: {self.config.get('eventType', 'trigger_email')}");
        self.status = "success";
        ctx["triggerType"] = self.config.get("eventType", "trigger_email");
        return ctx;
    }
}

node TriggerBlock :WorkflowBlock: {
    can execute(ctx: dict) -> dict {
        print(f"⚡ [TriggerBlock] Triggered event for: {self.title}");
        self.status = "success";
        ctx["trigger_time"] = "2026-07-26T11:00:00Z";
        ctx["text"] = "Urgent: Review JacHacks SF 2026 Submission Checkpoint by 5:50 PM!";
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
    else if (n.category === 'trigger') blockClass = 'TriggerBlock';
    else if (n.category === 'ai') blockClass = 'LLMTransformBlock';
    else if (n.category === 'mac') blockClass = 'MacAppBlock';
    else if (n.category === 'mcp') blockClass = 'MCPToolBlock';
    else if (n.category === 'output') blockClass = 'OutputBlock';

    const configJson = JSON.stringify(n.config || {});
    code += `    ${varName} = spawn node::${blockClass}(
        id="${n.id}",
        block_type="${n.type}",
        title="${n.title.replace(/"/g, '\\"')}",
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
