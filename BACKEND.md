# Swirl Backend Integration Contract

The backend is exposed through Tauri commands. Import `invoke` and `listen`:

```js
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
```

## Prompt and Jac commands

```js
const health = await invoke('backend_health');

const workflow = await invoke('compile_prompt', {
  prompt: 'Organize my Desktop and create an Apple Note',
  useLlm: false
});

const source = await invoke('generate_jac_source', {
  workflow: { nodes, edges }
});
```

`useLlm: true` calls Jac `by llm()` and requires a supported provider environment variable. The deterministic rules compiler remains available offline.

## Workflow execution and events

Register the event listener before invoking:

```js
const unlisten = await listen('swirl-workflow-event', ({ payload }) => {
  // event: start | node_start | node_complete | approval_required
  //        node_error | complete | failed
  console.log(payload);
});

const summary = await invoke('execute_workflow', {
  request: {
    nodes,
    edges,
    context: { text: 'Optional initial input' },
    approvals: []
  }
});
```

If an event has `event: "approval_required"`, show a confirmation dialog. To resume, invoke the workflow again with that node ID in `approvals`. File moves/organization, arbitrary shell commands, Calendar event creation, email sending, and external webhooks are gated.

Execution uses the Jac-generated topological plan, rejects duplicate IDs, dangling edges and cycles, emits every node transition, and writes a local trace to the Tauri application-data directory.

## Typed macOS command

```js
const result = await invoke('execute_mac_action', {
  request: {
    app: 'Notes',
    action: 'create_note',
    params: {
      title: 'Swirl Summary',
      content: 'Completed',
      folder: 'Swirl Automations'
    },
    approved: false
  }
});
```

Supported adapters:

- Notes: `create_note`, `append_note`, `search_notes`
- Finder: `list_files`, `create_folder`, `move`, `organize_by_extension`
- Mail: `create_draft`, `recent_messages`
- Calendar: `create_event`, `list_events`
- System: `display_notification`, `set_volume`
- Terminal: `exec_shell` (approval required)

The old raw AppleScript command remains narrowly restricted for compatibility with the current frontend bridge. New UI code should use `execute_mac_action`.

## MCP commands

Built-in MCP server definitions are owned by `backend/mcp_bridge.jac`. Tauri exposes
the catalog through `list_builtin_mcp_servers`; Rust remains the native transport
boundary for starting stdio processes and making HTTP requests.

```js
const builtIns = await invoke('list_builtin_mcp_servers');
```

```js
await invoke('register_mcp_server', {
  config: {
    name: 'filesystem',
    transport: 'stdio',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-filesystem', '/Users/me/Documents'],
    env: {}
  }
});

const servers = await invoke('list_mcp_servers');
const discovery = await invoke('discover_mcp_tools', { name: 'filesystem' });
const result = await invoke('call_mcp_tool', {
  name: 'filesystem',
  tool: 'read_file',
  arguments: { path: '/Users/me/Documents/example.txt' }
});
```

HTTP MCP servers must use HTTPS, except for `localhost`/`127.0.0.1`. stdio sessions perform the MCP initialize handshake, use newline-delimited JSON-RPC, enforce a 15-second response timeout, and are terminated when the app exits.

## Persistence commands

```js
await invoke('save_workflow', {
  name: 'Daily Digest',
  workflow: { nodes, edges }
});
const saved = await invoke('list_workflows');
const record = await invoke('load_workflow', { name: 'Daily Digest' });
await invoke('delete_workflow', { name: 'Daily Digest' });
```

Workflow names are validated and files are written atomically inside Tauri-managed application data.
