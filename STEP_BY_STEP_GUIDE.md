# QuaZe Build and Demo Guide

QuaZe is a prompt-first agentic workflow builder for non-technical users. This
guide exercises its first supported workflow—the seven-block meeting-prep
proof—not arbitrary workflow generation.

## 1. Install and Verify

```bash
jac --version
jac install
jac check .
jac test
jac build --client web
```

The repository is pinned to Jac `0.34.7`.

## 2. Run Safely in Fixture Mode

```bash
jac start
```

Fixture mode uses only repository data under `fixtures/`. Confirm the UI labels
the compiler and connectors as deterministic/fixture-backed.

Run the golden flow:

1. Compile the default meeting-prep prompt.
2. Confirm all seven blocks are present.
3. Move Approval away from Save Brief and confirm validation fails.
4. Restore the order and validate.
5. Start the run.
6. Confirm it pauses at Approval and no output file exists.
7. Approve.
8. Confirm the same run resumes and creates one `Tomorrow Brief.md`.
9. Approve or retry again and confirm no duplicate artifact is created.
10. Confirm both relevant notes are cited and the irrelevant note is absent.

## 3. Prepare Live Demo Sources

Use only dedicated demo data.

### Calendar

Create the dedicated calendar and synthetic meetings with the idempotent setup
script:

```bash
osascript scripts/setup_demo_calendar.applescript
```

It creates only `QuaZe Demo`, `Apex design review`, and `Maya onboarding`.
Do not point QuaZe at a personal calendar. Runtime Calendar access is read-only.

### Obsidian

Install Obsidian from its official distribution, then install the official
filesystem MCP server:

```bash
npm install --global @modelcontextprotocol/server-filesystem
```

Open `fixtures/demo-vault` once as its own Obsidian vault. QuaZe starts the MCP
server for each live read and passes that directory as its only allowed root.
Do not expose a home directory or personal vault.

### Hosted Prompt Compilation

Hosted compilation is optional. Configure its model and credential only through
environment variables supported by the runtime. Do not add credentials to
`jac.toml`, source files, shell scripts, screenshots, or commits.

## 4. Verify Live Evidence

Select **Live demo**, repeat the golden flow, and confirm:

- Calendar evidence names the dedicated calendar and bounded time range.
- Vault evidence identifies the dedicated vault and MCP transport.
- Approval creates a persisted event before Save Brief runs.
- Resume uses the same run ID and does not repeat completed steps.
- The saved path and content hash match the artifact shown in the UI.
- Open Result opens the saved file in Obsidian.

You can also run the connector-only opt-in checks:

```bash
jac run tests/live_calendar_opt_in.jac
jac run tests/mcp_connector_opt_in.jac
```

Fixture success does not prove live Calendar, MCP, macOS permission, or Obsidian
behavior.

## 5. Demo Freeze

Run the complete flow three consecutive times. Then:

```bash
jac check . --no-nowarn
jac test -v
jac build --client web
python3 -m py_compile connector_host.py
git diff --check
git status --short
```

Record the full golden flow as a fallback video. Verify repository and
submission links while logged out before claiming they are public.
