# Swirl

Swirl is a local-first macOS visual automation app powered by Jac graph walkers and Tauri v2.

The React canvas maps blocks to Jac nodes and edges. The native backend asks Jac to compile prompts, validate and plan workflow graphs, and generate Jac source. Tauri then executes permission-gated macOS actions and MCP calls while streaming node events back to the UI.

## Run locally

Requirements:

- macOS 12+
- Jac 0.34.7 (`jac --version`)
- Rust/Cargo
- Node.js and npm

```bash
cd frontend
npm ci
npm run tauri:dev
```

Swirl locates Jac from `SWIRL_JAC_BIN`, an app-bundled `bin/jac`, `~/.local/bin/jac`, `~/.jac/bin/jac`, Homebrew, or `PATH`.

## Validate the backend

```bash
jac check main.jac backend
jac clean --data --force
jac test backend/engine_tests.jac -v

cd frontend/src-tauri
cargo test
```

The native IPC/event contract for frontend integration is documented in [BACKEND.md](BACKEND.md).

## Backend layout

- `backend/workflow_agent.jac` — graph nodes, prompt compiler, LLM abilities, and execution walker.
- `backend/mac_control.jac` — macOS action policy walker.
- `backend/mcp_bridge.jac` — MCP JSON-RPC request walkers.
- `backend/code_generator.jac` — visual graph to Jac source generator.
- `backend/swirl_runtime.jac` — structured CLI adapter used by Tauri.
- `frontend/src-tauri/src/` — native IPC, approvals, AppleScript, MCP transports, persistence, and event streaming.

There is no FastAPI server or public WebSocket. All communication remains inside the Tauri app.
