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
export NVIDIA_API_KEY="nvapi-..."
jac install

cd frontend
npm ci
npm run tauri:dev
```

Swirl locates Jac from `SWIRL_JAC_BIN`, an app-bundled `bin/jac`, `~/.local/bin/jac`, `~/.jac/bin/jac`, Homebrew, or `PATH`.
AI Builder generation uses NVIDIA NIM through Jac/LiteLLM with
`meta/llama-3.3-70b-instruct`. Swirl accepts either `NVIDIA_API_KEY` (the name
used by NVIDIA's hosted examples) or `NVIDIA_NIM_API_KEY` (the name expected by
LiteLLM), inherits it from the Tauri process, and never asks for or stores the
key in the app.

Voice Source workflows long-poll the teammate-owned local Whisper service at
`http://127.0.0.1:8765/v1/events/next` by default. Override it with
`SWIRL_WHISPER_URL`. The endpoint accepts
`{"wakeWord","language","timeoutSec"}` and returns
`{"transcript","timestampMs","confidence"}`; HTTP 204 or 408 means no event yet.

## Validate the backend

```bash
jac check main.jac backend
jac clean --data --force
jac test backend/engine_tests.jac -v

# Optional live provider smoke test
SWIRL_RUN_LLM_SMOKE=1 jac test backend/engine_tests.jac

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
