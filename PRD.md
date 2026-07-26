# Product Requirements Document (PRD)

## Project Title: **Swirl — AI Visual Scratch-Block Editor & macOS MCP Control Center**
**Event:** JacHacks SF 2026 (Hosted by Jaseci Labs @ Founders, Inc., San Francisco)  
**Track Alignment:** Agentic AI ($2,000) • Best JacHammer ($500) • Best Use of Jaclang ($400) • Fintech / Open  
**Jac Content ratio:** > 45% of total codebase logic written in `.jac` files  

---

## 1. Executive Summary & Vision

**Swirl** is an AI-powered visual workflow studio designed specifically for non-technical users, founders, and creators. By combining natural language prompting with a visual, Scratch-style block builder and the **Model Context Protocol (MCP)**, Swirl enables anyone to automate local macOS apps (Finder, Mail, Notes, Calendar, System Controls, Browser, Terminal) and cloud APIs without writing a single line of code manually.

Under the hood, Swirl compiles every visual workflow block directly into **Jaclang** (`.jac`) code—the AI-native programming language developed by Jaseci Labs. Swirl leverages Jac’s native Graph-Walker architecture, `node` constructs, and `by llm()` capabilities to orchestrate resilient multi-agent execution paths, execute macOS automation scripts, and bridge to local MCP servers.

---

## 2. Problem Statement

1. **High Barrier to Desktop & Agentic Automation:** Powerful desktop automation tools (e.g. AppleScript, Automator, Raycast Scripts, LangChain, MCP clients) require programming knowledge, API handling, terminal navigation, or complex JSON configurations.
2. **Opaque AI Workflow Engines:** Existing visual automation tools (n8n, Zapier) rely on rigid proprietary schemas rather than open, inspectable code, making customization, offline execution, and agentic reasoning difficult.
3. **Lack of Native AI Agent Abstractions:** Traditional visual block builders lack native graph traversal and multi-agent coordination primitives required for modern autonomous task execution.

---

## 3. The Solution: Swirl

Swirl bridges the gap between natural language intent, visual Scratch-style block building, and native **Jaclang** agent execution:

1. **Prompt-to-Workflow AI Compiler:** Users describe what they want in plain English (e.g., *"When I get a high priority email, summarize it using LLM, create a task in Apple Notes, and notify me on Slack"*). Jac-powered LLM walkers generate the visual node graph automatically.
2. **Scratch-Style Visual Block Editor:** Drag-and-drop colorful blocks representing Jac Nodes (`TriggerNode`, `LLMTransformNode`, `MacAppNode`, `MCPToolNode`, `ConditionNode`, `OutputNode`).
3. **Bi-Directional Jac Code Synchronization:** Real-time generation of human-readable, executable `.jac` source code. Non-technical users see blocks; developers can switch to the Jac code view to inspect, export, or tweak the generated Jac Walkers.
4. **macOS App & MCP Bridge:** Native tool adapters for Apple Notes, Mail, Finder, System Settings, Slack, Web Scraping, and any stdio/HTTP Model Context Protocol (MCP) server.
5. **Live Walker Visual Inspector:** As the Jac walker traverses the graph, nodes light up in real-time, showing execution flow, intermediate state, and outputs.

---

## 4. Key Features & Functionality

| Feature | Description | Jac Technical Underpinnings |
| :--- | :--- | :--- |
| **Prompt-to-Blocks AI** | Natural language text bar translates user prompts into visual Scratch workflow nodes. | `by llm()` Jac function and `PromptToWorkflowWalker` AST emitter. |
| **Visual Block Editor** | Colorful, Scratch-inspired drag-and-drop node canvas with snapped connectors and parameter inputs. | Front-end React Flow canvas mapping 1:1 to Jac graph node topology. |
| **Jac Native Code Emitter** | Real-time code panel showing generated `.jac` source code matching the visual layout. | Jac AST Serializer converting visual block graph into `.jac` code files. |
| **macOS App Control** | Control local Mac applications (Notes, Finder, Safari, Calendar, Mail, Terminal). | `MacControlWalker` invoking AppleScript & macOS system APIs through Jac. |
| **MCP Integration** | Connect to external or local Model Context Protocol tools via stdio/HTTP. | `MCPBridgeWalker` handling JSON-RPC tool discovery and execution. |
| **Live Walker Inspector** | Visual animation of agent execution step-by-step with real-time logs and output cards. | Jac Walker event hooks sending WebSocket step updates to UI. |

---

## 5. System Architecture

```
                                  +---------------------------------------+
                                  |       Swirl Web Frontend (UI)         |
                                  | React + Vite + Visual Block Canvas    |
                                  +-------------------+-------------------+
                                                      |
                                        HTTP / WS API | Prompt / Exec
                                                      v
                                  +-------------------+-------------------+
                                  |    FastAPI / Jac Execution Engine     |
                                  +-------------------+-------------------+
                                                      |
                   +----------------------------------+----------------------------------+
                   |                                                                     |
                   v                                                                     v
    +--------------+---------------+                                      +--------------+---------------+
    |  Jaclang Multi-Agent Core    |                                      |      macOS & MCP Bridge      |
    |  (40%+ codebase in .jac)     |                                      |                              |
    |  - workflow_agent.jac        |                                      | - macOS AppleScript Executor |
    |  - mcp_bridge.jac            |                                      | - Stdio / HTTP MCP Clients   |
    |  - code_generator.jac        |                                      | - System Event Listener      |
    +------------------------------+                                      +------------------------------+
```

---

## 6. Jaclang Integration Strategy (40%+ Code Base Requirement)

Jac is central to Swirl's backend architecture. Over 40% of the core logic resides in `.jac` files:

1. `workflow_agent.jac`: Defines `WorkflowNode`, `WalkerContext`, `WorkflowExecutorWalker`, and `PromptToWorkflowWalker`.
2. `mcp_bridge.jac`: Defines `MCPToolNode`, `MCPDiscoveryWalker`, and `MCPExecuteWalker`.
3. `mac_control.jac`: Defines `MacAppNode` and `MacScriptWalker` for controlling local macOS apps.
4. `code_generator.jac`: Emitter walker that converts graph AST nodes into formatted Jac source code.

---

## 7. Hackathon Track & Award Strategy

- 🏆 **Best JacHammer ($500):** Deepest use of Jac primitives (`node`, `walker`, `with entry`, `by llm()`, `spawn`, graph traversal).
- 🏆 **Best Use of Jaclang ($400):** Clean architectural integration of Jac with external protocols (MCP & AppleScript).
- 🏆 **Agentic AI Track ($2,000 / $1,000):** Fully autonomous agent that takes intent, constructs its own node graph, executes multi-step macOS workflows, and self-corrects on errors.

---

## 8. Hackathon Target User Stories

1. **User Story 1 (Non-Technical Founder):**  
   *"As a non-technical founder, I want to type 'Organize my Desktop files into folders by file extension and write a report in Apple Notes', so that Swirl generates visual blocks, converts them to Jac, and executes the task on my Mac."*

2. **User Story 2 (AI Enthusiast):**  
   *"As an AI hacker, I want to connect an external MCP server to Swirl and see it appear as a Scratch block that I can snap into a Jac agent workflow."*

3. **User Story 3 (Jac Judge / Dev):**  
   *"As a JacHacks judge, I want to toggle the 'Jac Code View' to inspect the clean Jac source code generated live by the visual editor."*

---

## 9. Success Metrics & Key Deliverables

- [x] Functional prompt-to-workflow AI block generation.
- [x] Visual Scratch-style canvas with drag-and-drop & editing.
- [x] Live Jac source code sync & compiler.
- [x] Working execution engine running Jac walkers.
- [x] macOS AppleScript integration (Apple Notes, Finder, System).
- [x] MCP Protocol tool bridge demonstration.
- [x] Demo video & Devpost submission ready before 5:50 PM checkpoint.
