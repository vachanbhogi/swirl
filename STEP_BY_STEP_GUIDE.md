# STEP_BY_STEP_GUIDE.md — Hackathon Implementation & Submission Guide

**Event:** JacHacks SF 2026 @ Founders, Inc., San Francisco  
**Project:** Swirl — AI Visual Scratch-Block Editor & macOS MCP Control Center  
**Target Deadline:** 5:50 PM (Partial Checkpoint) / 7:15 PM (Final Hard Deadline)  

---

## Phase 1: Environment & Jac Core Setup (0-30 mins)

1. **Install and verify the Jac CLI:**
   ```bash
   python3 -m pip install jaclang==0.34.7
   jac --version
   ```
2. **Structure the Jac core (`/backend`):**
   - Create `backend/workflow_agent.jac`: Core Jac nodes, walker graph executor, and LLM transform rules.
   - Create `backend/mcp_bridge.jac`: MCP tool discovery and JSON-RPC execution walker.
   - Create `backend/mac_control.jac`: AppleScript wrappers for macOS apps (Notes, Finder, Mail, System).
   - Create `backend/code_generator.jac`: Visual graph to Jac source walker.
   - Create `backend/swirl_runtime.jac`: Structured adapter invoked by the native process.
3. **Use `frontend/src-tauri/src/` for the native boundary:**
   - Typed Tauri commands and local events.
   - Permission-gated AppleScript and filesystem operations.
   - MCP stdio/HTTP process lifecycle.
   - Tauri-managed workflow and trace persistence.

---

## Phase 2: Building the Jac Engine Backend (30-90 mins)

1. **Implement `workflow_agent.jac`:**
   - Define `WorkflowBlock` base node and concrete block classes (`TriggerBlock`, `LLMTransformBlock`, `MacAppBlock`, `MCPToolBlock`, `ConditionBlock`).
   - Implement `WorkflowExecutorWalker` to step through graph nodes.
   - Implement `PromptToWorkflowWalker` using `by llm()` to map text prompts to JSON block ASTs.
2. **Implement the macOS policy walker and Rust executor (`mac_control.jac` / `src-tauri/src/macos.rs`):**
   - Create AppleScript handlers for:
     - **Apple Notes:** `osascript -e 'tell application "Notes" to make new note with properties {body:"..."}'`
     - **Finder:** File list & directory operations.
     - **System:** `osascript -e 'display notification "..." with title "Swirl Workflow"'`
3. **Implement the MCP Bridge (`mcp_bridge.jac` / `src-tauri/src/mcp.rs`):**
   - Connect stdio / HTTP MCP servers.
   - Expose discovery and execution through typed Tauri commands.

---

## Phase 3: Building the Visual Scratch-Style UI Frontend (90-180 mins)

1. **Initialize Vite React Frontend (`/frontend`):**
   ```bash
   npm create vite@latest frontend -- --template react
   cd frontend
   npm install @xyflow/react lucide-react clsx tailwindcss postcss autoprefixer axios
   ```
2. **Design System & Aesthetics:**
   - Implement modern dark/glassmorphic theme with colorful Scratch-style block nodes (Purple = Triggers, Amber = AI/LLM, Blue = macOS Apps, Emerald = MCP Tools, Red = Outputs).
3. **Build Core Components:**
   - `PromptBar.jsx`: Top natural language prompt input ("Prompt your workflow...").
   - `ScratchCanvas.jsx`: Interactive visual node flow editor using React Flow.
   - `BlockPalette.jsx`: Sidebar with drag-and-drop tool blocks (Apple Notes, Mail, Finder, MCP Tools, LLM Summarizer).
   - `JacCodeViewer.jsx`: Split-screen panel displaying live generated `.jac` code side-by-side with visual blocks.
   - `ExecutionInspector.jsx`: Bottom drawer with live log stream, node execution state, and output cards.

---

## Phase 4: Integration & Bi-Directional Compiler (180-240 mins)

1. **Prompt-to-Blocks Pipeline:**
   - User types: *"Summarize my latest notes and save to Desktop file"* -> Tauri `compile_prompt` command -> Jac Walker generates AST -> React renders the visual block pipeline.
2. **Live Jac Code Generation:**
   - As blocks are added or edited on canvas, frontend calls Jac code generator to sync `.jac` source code view in real time.
3. **Live Execution & Walker Visualizer:**
   - User clicks **"▶ Run Workflow"** -> Tauri `execute_workflow` command -> Jac `WorkflowExecutorWalker` plans graph traversal -> `swirl-workflow-event` streams native events -> Active node glows green in UI.

---

## Phase 5: Demo Scenarios & Submission Checklist (Final Hours)

### Demo Scenario 1: macOS Automation (Apple Notes & Finder)
1. User prompts: *"Summarize text using LLM and create an Apple Note on my Mac"*.
2. Swirl builds visual Scratch blocks.
3. User views generated `.jac` source code.
4. User clicks **Run**. Apple Notes opens on Mac with the newly generated note!

### Demo Scenario 2: MCP Tool Integration
1. Select MCP filesystem / web search tool block.
2. Connect to LLM transform and Mac notification.
3. Execute workflow and observe live walker traversal.

### Devpost Submission Checklist:
- [x] **Project Name:** Swirl
- [x] **Tagline:** AI Visual Scratch-Block Editor & macOS MCP Control Center Powered by Jaclang
- [x] **GitHub Repository:** Include link and ensure >= 40% of codebase is `.jac` files.
- [x] **GitHub Star Jac:** Star `https://github.com/jaseci-labs/jac`
- [x] **Demo Video:** Record 2-minute walkthrough showing visual prompt-to-blocks, Jac code sync, and live Mac execution.
- [x] **Track Selection:** Agentic AI, Best JacHammer, Best Use of Jaclang, Fintech/Open.
- [x] **Partial Submission Checkpoint:** Submit before 5:50 PM!
