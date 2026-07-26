# QuaZe

QuaZe is a prompt-first agentic workflow builder for non-technical users. A
person describes an outcome in plain language; QuaZe turns it into an
inspectable Jac graph that they can edit, validate, approve, run, and audit
without writing code.

The current MVP proves that product through one deliberately narrow workflow:
preparing tomorrow's meeting brief from a dedicated Calendar and Obsidian demo
vault. Its seven allowlisted blocks demonstrate prompt compilation, meaningful
graph editing, deterministic validation, connector evidence, human approval,
an idempotent artifact, and a visible execution trace. This build does not yet
generate or execute arbitrary workflows.

## Current Status

The golden workflow is implemented end to end. The Jac client calls real
public walkers, execution and approval state persist in the Jac graph, fixture
and live connectors are visibly distinguished, and the approved brief is
written idempotently before Obsidian opens it.

No personal Calendar or vault data is used. Fixture results, deterministic
fallbacks, live Calendar access, live MCP access, and unavailable integrations
must remain visibly distinct.

## Requirements

- macOS
- Jac `0.34.7`
- Bun or Node for the Jac client toolchain
- Python 3
- Obsidian and the official filesystem MCP server for the live demo

## Fixture Setup

```bash
jac --version
jac install
jac start
```

Open the local URL printed by `jac start`. Fixture mode is the default and
uses only repository-owned synthetic data; Calendar, MCP, and Obsidian are not
required for this path.

Build the production web client with:

```bash
jac build --client web
```

## Live Demo Setup

Install Obsidian from its official distribution and install the official
filesystem MCP server:

```bash
npm install --global @modelcontextprotocol/server-filesystem
```

Create the dedicated synthetic Calendar data. The script is idempotent and
never touches another calendar:

```bash
osascript scripts/setup_demo_calendar.applescript
```

Open `fixtures/demo-vault` once as its own Obsidian vault. Then start QuaZe,
select **Live demo**, run the workflow, and approve it. Live mode reads only
tomorrow's events from `QuaZe Demo`, starts the filesystem MCP server with only
the demo-vault path, saves `Tomorrow Brief.md`, and opens that note through an
Obsidian URI.

Hosted prompt compilation is optional. Configure the model through the Jac
byLLM runtime environment; never add credentials to this repository. Missing
configuration, network errors, invalid output, and unsupported intent use a
visibly labeled deterministic path.

## Verification

```bash
jac check . --no-nowarn
jac test -v
jac build --client web
python3 -m py_compile connector_host.py
```

The live connector checks are opt-in because they require local macOS data and
installed software:

```bash
jac run tests/live_calendar_opt_in.jac
jac run tests/mcp_connector_opt_in.jac
```

## Safe Demo Data

QuaZe uses only a dedicated demo calendar named `QuaZe Demo` and a dedicated
Markdown vault under `fixtures/demo-vault`.

The synthetic fixture contains:

- `Apex design review`
- `Maya onboarding`
- a matching Apex project note
- a matching Maya people note
- one irrelevant note used to prove retrieval precision

The generated `fixtures/demo-vault/Tomorrow Brief.md` is ignored by Git.

## Architecture

- `contracts.sv.jac` — typed view contracts and persistent graph schema
- `workflow.sv.jac` — deterministic seven-block workflow
- `compiler.sv.jac` — typed hosted compiler and deterministic fallback
- `runtime.sv.jac` — deterministic validation and fixture execution helpers
- `connectors.sv.jac` / `connector_host.py` — bounded connector boundary
- `graph_store.sv.jac` — workflow revisions, runs, evidence, and artifacts
- `executor.sv.jac` — persisted graph traversal and approval resume
- `endpoints.sv.jac` — public lifecycle walkers
- `frontend.cl.jac` — Jac client entry
- `main.jac` — full-stack entry point

The shared contracts are intentionally workflow-shaped rather than
meeting-shaped. New workflow types can eventually reuse the graph, validation,
run, approval, evidence, and artifact lifecycle, but supporting additional
blocks and connectors requires explicit implementation and verification.

The public walkers are `compile_prompt`, `validate_workflow`,
`reorder_blocks`, `start_run`, `approve_run`, and `get_run`.

## Safety

- Calendar is read-only and bounded to the dedicated demo calendar.
- Vault paths must remain inside the dedicated demo vault.
- Save is gated by a real persisted approval state.
- Workflow input cannot execute arbitrary shell commands.
- Hosted model credentials are environment-only and optional.

See [PRD.md](PRD.md) for acceptance criteria and
[AGENT_HANDOFF.md](AGENT_HANDOFF.md) for parallel ownership.
