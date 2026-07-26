# QuaZe Parallel Agent Handoff

This file is the coordination contract for parallel implementation. The main
agent working in `/Users/nihar/Desktop/QuaZe` is the integration lead and owns
architecture, shared contracts, merges, dependency decisions, and final
verification.

## Product Goal

QuaZe's product vision is a prompt-first agentic workflow builder for
non-technical users: describe an outcome, inspect and edit the generated graph,
validate it, approve sensitive actions, run it, and audit the trace without
writing code.

Calendar, Obsidian, and meeting preparation are only the controlled demo used
to prove those reusable workflow primitives. QuaZe is not a calendar,
meeting-prep, or productivity product. Product copy and implementation
decisions must center the one-prompt workflow-creation experience.
Do not expand Calendar-specific functionality beyond the minimum bounded demo
adapter.

The implementation goal for this handoff is to prove that reusable lifecycle
through one narrow macOS meeting-prep workflow:

> prompt -> editable Jac graph -> validation -> Calendar + Obsidian retrieval
> -> draft -> approval pause -> saved brief -> visible trace

The golden workflow has exactly seven ordered blocks:

1. Run Now
2. Read Calendar
3. Search Vault
4. Draft Brief
5. Approval
6. Save Brief
7. Open Result

The graph, execution state, approval lifecycle, and persisted trace must live in
Jac. The UI must use Jac's built-in full-stack client rather than a separate
JavaScript application.

The interface may communicate the broader prompt-to-workflow product, but it
must label meeting preparation as the first supported workflow and must not
claim that arbitrary workflows or tools already execute.

## Main Integration Lead

Working directory: `/Users/nihar/Desktop/QuaZe`

Owns:

- `AGENTS.md`, `PRD.md`, `README.md`, `STEP_BY_STEP_GUIDE.md`
- `jac.toml`, `main.jac`
- shared contract and graph-schema files
- public walker declarations and API boundaries
- approval and persisted-run integration
- dependency, schema, and architecture decisions
- branch review, integration, final checks, and demo acceptance

The integration lead is the only agent allowed to change frozen contracts,
public walker signatures, dependencies, schemas, or persistent-data formats.
Agents must report a needed contract change instead of making it.

## Contract Gate

Do not edit implementation files until the integration lead publishes the
contract commit hash and creates the isolated worktrees. Before that gate, an
agent may inspect the repository, Jac 0.34.7 behavior, and official Jac
documentation, but must not commit changes.

Frozen public walkers:

- `compile_prompt`
- `validate_workflow`
- `reorder_blocks`
- `start_run`
- `approve_run`
- `get_run`

Frozen shared models:

- `WorkflowSpec`
- `BlockSpec`
- `ConnectionSpec`
- `ValidationResult`
- `ConnectorResult`
- `RunState`
- `RunStepSpec`
- `ApprovalSpec`
- `ArtifactSpec`
- `AgentEventSpec`
- `DemoState`

Frozen graph entities:

- `Workflow`
- `Block`
- `Run`
- `RunStep`
- `Approval`
- `Artifact`
- `AgentEvent`

Frozen execution states:

- Run: `idle`, `running`, `awaiting_approval`, `succeeded`, `failed`
- Step: `pending`, `running`, `succeeded`, `awaiting_approval`, `skipped`,
  `failed`

## Runtime and Tests Agent

Branch: `agent/runtime-tests`
Worktree: `/Users/nihar/Desktop/QuaZe-runtime`

Owns only:

- runtime implementation modules assigned by the integration lead
- Calendar and vault connector modules
- `fixtures/`
- runtime and scenario tests

Must not edit:

- client files
- shared contract definitions
- public walker signatures
- project dependencies or `jac.toml`
- repository documentation except a scoped runtime note requested by the lead

Required work:

1. Implement deterministic workflow validation for unsupported blocks, missing
   inputs, cycles, unreachable steps, unavailable connectors, and writes
   without an immediately preceding Approval block.
2. Implement a bounded read-only Calendar adapter that defaults to fixture mode
   and accesses only the configured dedicated demo calendar in live mode.
3. Implement a dedicated-vault adapter with explicit path containment.
4. Implement filesystem MCP discovery/call support for the dedicated demo
   vault, with a labeled safe direct-filesystem fallback when MCP is
   unavailable.
5. Seed only synthetic data:
   - `Apex design review` plus a matching project note
   - `Maya onboarding` plus a matching people note
   - one irrelevant note that must not appear in the final brief
6. Implement deterministic drafting with source references and a clear missing
   context marker.
7. Make `Tomorrow Brief.md` idempotent: resume/retry must produce exactly one
   artifact.
8. Add Jac scenarios covering every acceptance case listed below.

Return to the integration lead:

- commit hash
- files changed
- exact commands run and results
- one remaining risk
- any requested contract change, without implementing that change

## UI and Demo Agent

Branch: `agent/ui-demo`
Worktree: `/Users/nihar/Desktop/QuaZe-ui`

Owns only:

- Jac client files assigned by the integration lead
- client components and scoped styles
- UI-focused tests or demo fixtures explicitly assigned by the lead

Must not edit:

- runtime or connector files
- shared contract definitions
- public walker signatures
- project dependencies or `jac.toml`
- repository documentation unless requested

Required work:

1. Build one focused screen against `DemoState`.
2. Include the prompt, seven-block library, editable vertical flow, selected
   block inspector, validation results, run control, approval panel, trace, and
   artifact reveal.
3. Call the real public Jac walkers. Do not add mock API routes.
4. Provide stable move-up/move-down controls. Drag-and-drop is optional.
5. Represent status consistently:
   - neutral: pending/idle
   - blue: running
   - green: succeeded
   - amber: awaiting approval
   - red: failed/invalid
6. Present QuaZe as a prompt-first workflow builder while clearly labeling
   meeting preparation as the only supported workflow in this build. Avoid
   generic dashboard cards, glassmorphism, unsupported automation claims, and
   fake live state.
7. Support keyboard focus, reduced motion, and a useful narrow-screen layout.

Design direction:

- Audience: a founder preparing for tomorrow's meetings on their own Mac.
- Single job: inspect and safely run tomorrow's brief workflow.
- Visual signature: the seven-block execution spine doubles as the live trace.
- Palette: ink `#17202A`, paper `#F5F7F8`, signal blue `#2364AA`, success
  `#2E7D5B`, approval amber `#B7791F`, failure red `#B33A3A`.
- Typography: system sans for interface text and system mono for evidence,
  paths, hashes, and trace metadata. Do not add a font dependency.

Return to the integration lead:

- commit hash
- files changed
- exact commands run and results
- screenshots at desktop and narrow widths if the app can run
- one remaining risk
- any requested contract change, without implementing that change

## Safety Boundaries

- Never access personal calendars or vaults.
- Never write to Calendar.
- Never store API keys, model credentials, tokens, or personal data.
- Never run arbitrary shell blocks from user input.
- Do not claim all-local inference: hosted prompt compilation is optional and
  must be configured through environment variables.
- Do not claim MCP or live Calendar success from fixture results.
- Do not install dependencies or applications without the integration lead's
  explicit coordination.
- Do not commit, push, merge, or deploy outside the assigned branch.
- Preserve unrelated changes. Never reset, clean, or delete another agent's
  worktree or files.

## Required Acceptance Scenarios

- The golden prompt produces only the seven supported blocks.
- Unsupported tools fail or activate the visibly labeled deterministic
  fallback.
- Moving Approval away from Save Brief makes validation fail.
- Connector failure stops the run, exposes evidence, and creates no artifact.
- Approval pauses without executing Save Brief.
- Approval resumes the same run without repeating completed steps.
- Repeated resume/retry produces exactly one artifact.
- The brief cites both matched fixture records, excludes the irrelevant note,
  and marks missing context.
- Persisted Jac state and the client trace agree.

## Integration Protocol

1. Wait for the contract commit hash and worktree assignment.
2. Rebase or restart only when the integration lead instructs it.
3. Stay inside owned files.
4. Run `jac check .` and the scoped Jac tests before handoff.
5. Do not merge your branch.
6. Send the required handoff report to the integration lead.
7. The integration lead reviews and integrates one branch at a time, running
   the full checks after each integration.

## Current Status

- Repository audit and contract freeze: complete
- Jac version verified: `0.34.7`
- Canonical remote: `https://github.com/vachanbhogi/swirl.git`
- Contract commit: `b53333d` (`feat: establish QuaZe meeting prep contracts`)
- Runtime handoff: complete at `68aaae5`, integrated by `c40969c`
- UI handoff: complete at `ee75ab7`, integrated by `70015bf`
- Integration review: complete; workflow revision, validation, approval,
  fallback, and artifact findings were addressed centrally
- Obsidian `1.12.7`: installed and configured only with
  `fixtures/demo-vault`
- Filesystem MCP `2026.7.10`: installed and live path containment verified
- Dedicated `QuaZe Demo` Calendar: seeded with the two synthetic meetings
- Desktop, narrow-screen, live connector, approval, Obsidian reveal, and three
  consecutive idempotent run checks: complete
- Push/deployment/submission: not performed
