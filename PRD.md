# Product Requirements Document (PRD)

## Project Title: **Swirl — AI Visual Workflow Desktop App & macOS MCP Control Center**
**Event:** JacHacks SF 2026 (Hosted by Jaseci Labs @ Founders, Inc., San Francisco)  
**Track Alignment:** Agentic AI ($2,000) • Best JacHammer ($500) • Best Use of Jaclang ($400) • Fintech / Open  
**Jac Content ratio:** > 45% of total codebase logic written in `.jac` files  

---

## 1. Executive Summary & Vision

**Swirl** is a local-first, Tauri-powered macOS desktop application designed specifically for non-technical users, founders, and creators. By combining natural language prompting with a visual, Scratch-style block builder and the **Model Context Protocol (MCP)**, Swirl enables anyone to automate local macOS apps (Finder, Mail, Notes, Calendar, System Controls, Browser, Terminal) and cloud APIs without writing a single line of code manually.

The product ships as a native `.app` bundle rather than a hosted web frontend. Tauri provides the desktop window, secure local IPC, native permission handling, system integrations, and process lifecycle management. Under the hood, Swirl compiles every visual workflow block directly into **Jaclang** (`.jac`) code—the AI-native programming language developed by Jaseci Labs. Swirl leverages Jac’s native Graph-Walker architecture, `node` constructs, and `by llm()` capabilities to orchestrate resilient multi-agent execution paths, execute macOS automation scripts, and bridge to local MCP servers.

---

## 2. Problem Statement

1. **High Barrier to Desktop & Agentic Automation:** Powerful desktop automation tools (e.g. AppleScript, Automator, Raycast Scripts, LangChain, MCP clients) require programming knowledge, API handling, terminal navigation, or complex JSON configurations.
2. **Opaque AI Workflow Engines:** Existing visual automation tools (n8n, Zapier) rely on rigid proprietary schemas rather than open, inspectable code, making customization, offline execution, and agentic reasoning difficult.
3. **Lack of Native AI Agent Abstractions:** Traditional visual block builders lack native graph traversal and multi-agent coordination primitives required for modern autonomous task execution.
4. **Poor Fit Between Browser Sandboxes and Desktop Automation:** A browser-based frontend cannot directly manage local processes, macOS permissions, AppleScript, filesystem access, or stdio MCP servers without a separate local service.

---

## 3. The Solution: Swirl

Swirl bridges the gap between natural language intent, visual Scratch-style block building, and native **Jaclang** agent execution:

1. **Prompt-to-Workflow AI Compiler:** Users describe what they want in plain English (e.g., *"When I get a high priority email, summarize it using LLM, create a task in Apple Notes, and notify me on Slack"*). Jac-powered LLM walkers generate the visual node graph automatically.
2. **Scratch-Style Visual Block Editor:** Drag-and-drop blocks representing Jac Nodes (`TriggerNode`, `LLMTransformNode`, `MacAppNode`, `MCPToolNode`, `ConditionNode`, `OutputNode`).
3. **Bi-Directional Jac Code Synchronization:** Real-time generation of human-readable, executable `.jac` source code. Non-technical users see blocks; developers can switch to the Jac code view to inspect, export, or tweak the generated Jac Walkers.
4. **macOS App & MCP Bridge:** Native tool adapters for Apple Notes, Mail, Finder, System Settings, Slack, Web Scraping, and any stdio/HTTP Model Context Protocol (MCP) server.
5. **Live Walker Visual Inspector:** As the Jac walker traverses the graph, nodes update state in real-time, showing execution flow, intermediate state, and outputs.
6. **Native Tauri Desktop Runtime:** The UI, Rust command layer, Jac execution runtime, and MCP processes run together as a signed local macOS application with no separately hosted frontend or backend service.

---

## 4. Key Features & Functionality

| Feature | Description | Jac Technical Underpinnings |
| :--- | :--- | :--- |
| **Prompt-to-Blocks AI** | Natural language text bar translates user prompts into visual Scratch workflow nodes. | `by llm()` Jac function and `PromptToWorkflowWalker` AST emitter. |
| **Visual Block Editor** | Scratch-inspired drag-and-drop node canvas with snapped connectors and parameter inputs inside the Tauri WebView. | TypeScript canvas state maps 1:1 to Jac graph node topology. |
| **Jac Native Code Emitter** | Real-time code panel showing generated `.jac` source code matching the visual layout. | Jac AST Serializer converting visual block graph into `.jac` code files. |
| **macOS App Control** | Control local Mac applications (Notes, Finder, Safari, Calendar, Mail, Terminal). | `MacControlWalker` invokes permission-gated Tauri/Rust commands for AppleScript and macOS APIs. |
| **MCP Integration** | Connect to external or local Model Context Protocol tools via stdio/HTTP. | `MCPBridgeWalker` handles JSON-RPC while the Tauri process manages local child processes and transport lifecycles. |
| **Live Walker Inspector** | Visual animation of agent execution step-by-step with real-time logs and output cards. | Jac Walker events stream to the UI through Tauri events rather than a public WebSocket server. |
| **Native Desktop Packaging** | Install and launch Swirl as a macOS `.app`, with application menus, permission prompts, and local persistence. | Tauri v2, Rust commands, scoped capabilities, bundled resources, and a managed Jac sidecar/runtime. |

---

## 5. System Architecture

```
                        +------------------------------------------------+
                        |          Swirl Tauri v2 Desktop App             |
                        |  TypeScript/Vite UI + Visual Workflow Canvas    |
                        +-----------------------+------------------------+
                                                |
                              Tauri IPC / Events | Prompt / Exec / Status
                                                v
                        +-----------------------+------------------------+
                        |       Rust Native Command & Safety Layer        |
                        | permissions • process lifecycle • persistence  |
                        +-----------------------+------------------------+
                                                |
                 +------------------------------+------------------------------+
                 |                                                             |
                 v                                                             v
    +------------+-----------------+                              +------------+-----------------+
    | Bundled Jac Execution Core   |                              |       macOS & MCP Bridge      |
    | (45%+ codebase in .jac)      |                              |                               |
    | - workflow_agent.jac         |                              | - AppleScript / macOS APIs    |
    | - mcp_bridge.jac             |                              | - Stdio / HTTP MCP clients    |
    | - mac_control.jac            |                              | - Tauri capability allowlist  |
    | - code_generator.jac         |                              | - Local event streaming       |
    +------------------------------+                              +-------------------------------+
```

---

### 5.1 Desktop Runtime Boundaries

1. **Tauri UI:** Renders the prompt bar, workflow canvas, property inspector, Jac code view, logs, and confirmation dialogs in the system WebView.
2. **Rust Command Layer:** Exposes a narrow set of typed Tauri commands for filesystem access, AppleScript execution, MCP process management, workflow persistence, and Jac runtime invocation.
3. **Jac Runtime:** Runs the graph-walker agents locally as a bundled sidecar/runtime. The Rust layer sends workflow inputs to Jac and converts execution output into Tauri events.
4. **Local Event Channel:** Workflow status, node transitions, logs, and approval requests use Tauri's event system. No FastAPI server, browser-accessible HTTP API, or public WebSocket listener is required for the MVP.
5. **Persistence:** Workflow projects, generated `.jac` files, execution traces, and MCP server configuration are stored in Tauri-managed application data directories.

---

## 6. Jaclang Integration Strategy (45%+ Code Base Requirement)

Jac is central to Swirl's execution architecture. At least 45% of the core application logic resides in `.jac` files:

1. `workflow_agent.jac`: Defines `WorkflowNode`, `WalkerContext`, `WorkflowExecutorWalker`, and `PromptToWorkflowWalker`.
2. `mcp_bridge.jac`: Defines `MCPToolNode`, `MCPDiscoveryWalker`, and `MCPExecuteWalker`.
3. `mac_control.jac`: Defines `MacAppNode` and `MacScriptWalker` for controlling local macOS apps.
4. `code_generator.jac`: Emitter walker that converts graph AST nodes into formatted Jac source code.

The Rust/Tauri layer remains intentionally thin: it owns native OS boundaries, permissions, child processes, and IPC, while workflow semantics, graph traversal, prompt-to-workflow generation, MCP orchestration, and code generation remain implemented in Jac.

---

## 7. Tauri Desktop Requirements

1. **Platform:** Tauri v2 application targeting macOS for the hackathon MVP.
2. **Frontend Assets:** TypeScript and Vite render the interface inside Tauri's system WebView; the product is not deployed as a standalone website.
3. **Native Commands:** All privileged operations must pass through typed Rust commands with input validation and explicit error responses.
4. **Runtime Bundling:** The release bundle must include or reliably locate the Jac runtime and required `.jac` sources without requiring the user to start a separate backend.
5. **Permissions:** The app must declare required macOS usage descriptions and Tauri capabilities. Automation, filesystem, shell, and network access are denied by default and enabled only for required commands.
6. **Window Lifecycle:** Closing, relaunching, or terminating the app must clean up Jac and MCP child processes.
7. **Offline Behavior:** Workflow editing, code generation, local execution, and macOS automation should work locally; only explicitly configured LLM or remote MCP calls require network access.

---

## 8. Hackathon Track & Award Strategy

- 🏆 **Best JacHammer ($500):** Deepest use of Jac primitives (`node`, `walker`, `with entry`, `by llm()`, `spawn`, graph traversal).
- 🏆 **Best Use of Jaclang ($400):** Clean architectural integration of Jac with external protocols (MCP & AppleScript).
- 🏆 **Agentic AI Track ($2,000 / $1,000):** Fully autonomous agent that takes intent, constructs its own node graph, executes multi-step macOS workflows, and self-corrects on errors.

---

## 9. Hackathon Target User Stories

1. **User Story 1 (Non-Technical Founder):**  
   *"As a non-technical founder, I want to type 'Organize my Desktop files into folders by file extension and write a report in Apple Notes', so that Swirl generates visual blocks, converts them to Jac, and executes the task on my Mac."*

2. **User Story 2 (AI Enthusiast):**  
   *"As an AI hacker, I want to connect an external MCP server to Swirl and see it appear as a Scratch block that I can snap into a Jac agent workflow."*

3. **User Story 3 (Jac Judge / Dev):**  
   *"As a JacHacks judge, I want to toggle the 'Jac Code View' to inspect the clean Jac source code generated live by the visual editor."*

---

## 10. Success Metrics & Key Deliverables

- [x] Functional prompt-to-workflow AI block generation.
- [x] Visual Scratch-style canvas with drag-and-drop & editing.
- [x] Live Jac source code sync & compiler.
- [x] Working execution engine running Jac walkers.
- [x] macOS AppleScript integration (Apple Notes, Finder, System).
- [x] MCP Protocol tool bridge demonstration.
- [ ] Tauri v2 macOS `.app` launches without a separately started web or API server.
- [ ] Tauri IPC and event streaming connect the UI to the Rust and Jac execution layers.
- [ ] App capabilities and macOS permission prompts protect privileged actions.
- [ ] Jac and MCP child processes are terminated cleanly when the app exits.
- [x] Demo video & Devpost submission ready before 5:50 PM checkpoint.
