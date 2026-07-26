# QuaZe Master Task Board

This file is the single source of truth for implementation status. Only the
main developer updates this board. Role-specific details live under `tasks/`.

## Status legend

- `[ ]` queued
- `[x]` verified complete
- `BLOCKED` cannot proceed until its named dependency is resolved

A task is complete only after its acceptance checks have been run. Existing
checkboxes in legacy files do not establish completion.

## Current repository reality

- The repository contains a minimal Jac CLI scaffold.
- Several files still describe an earlier, broader product named Swirl.
- No behavior in the legacy PRD is considered implemented until verified.
- The current `main.jac` only prints a greeting.
- The contract-freeze gate is currently **CLOSED**.

## Non-negotiable product scope

- Product name: **QuaZe**
- Primary track: **Agentic AI**, subject to current organizer confirmation
- Fixed workflow:
  `Run Now -> Read Calendar -> Search Obsidian -> Draft Brief -> Approval -> Save Brief -> Open Result`
- Core proof:
  a real Jac graph, a meaningful user edit, deterministic validation, bounded
  live connector evidence, approval pause/resume, one artifact, and one trace
- Demo data:
  a dedicated Calendar fixture and dedicated Obsidian demo vault only
- UI:
  one screen containing the block library, workflow, inspector, run controls,
  approval state, trace, and artifact

## Ownership and integration order

| Role | Owns | Must not edit |
| --- | --- | --- |
| Main developer | contracts, graph schema/library, executor, lifecycle, integration, release checks | Junior implementation files except during reviewed integration |
| Junior developer 1 | compiler, validator, Calendar/Obsidian adapters, focused tests | contracts, executor, client |
| Junior developer 2 | client canvas/components and client tests | contracts, runtime, connectors |

Work proceeds in this order:

1. Reconcile repository truth and verify the Jac toolchain.
2. Main developer freezes contracts and opens the contract gate.
3. Junior developers work in parallel within exclusive ownership.
4. Main developer integrates the fixed workflow end to end.
5. The team verifies the live path, fallbacks, security, and submission assets.

## Milestone 0 — Repository truth

- [ ] M0.1 Inspect the current source, dependencies, Git state, and available
  Jac commands.
- [ ] M0.2 Reconcile `Swirl` references to `QuaZe`.
- [ ] M0.3 Rewrite the legacy PRD and guide around the narrow meeting-prep
  workflow.
- [ ] M0.4 Remove or correct premature completion claims.
- [ ] M0.5 Remove unsupported claims about unrestricted Mac, Terminal, browser,
  mouse, keyboard, email, deletion, or dynamic MCP control.
- [ ] M0.6 Confirm the current organizer rules for track selection, code-start
  timing, Jac percentage, local apps, and MCP adapters before claiming
  compliance.
- [ ] M0.7 Document the exact verified Jac version and supported project/client
  commands.

Acceptance:

- No repository document presents legacy Swirl behavior as current QuaZe
  behavior.
- No unverified feature is marked complete.
- The project starts from a documented clean environment.

## Milestone 1 — Frozen contracts and fixture

- [ ] M1.1 Define typed `WorkflowSpec` and `BlockSpec` contracts.
- [ ] M1.2 Define connector request/result contracts and permission metadata.
- [ ] M1.3 Define `RunState`, `RunStep`, `AgentEvent`, `Approval`, and `Artifact`.
- [ ] M1.4 Define stable block IDs, port types, status values, and error codes.
- [ ] M1.5 Define deterministic validation rules and approval requirements.
- [ ] M1.6 Define the fixed meeting-prep `DemoState` used independently by the
  runtime tests and client.
- [ ] M1.7 Define the controlled demo calendar events, matching vault notes,
  irrelevant note, expected brief structure, and output path.
- [ ] M1.8 Record file ownership and the integration boundary.
- [ ] M1.9 Review the contracts for safety, idempotency, and UI/runtime parity.
- [ ] M1.10 Mark the contract-freeze gate **OPEN**.

Acceptance:

- The client and runtime consume the same IDs, states, events, and artifacts.
- Unsupported tools cannot be represented by the allowlisted schema.
- Every write block declares that approval is required.
- Junior agents can work without editing contract files.

## Milestone 2A — Jac graph and execution lifecycle

Owner: main developer. Details: `tasks/MAIN_DEVELOPER.md`.

- [ ] M2A.1 Store the fixed workflow as real Jac nodes and edges.
- [ ] M2A.2 Implement deterministic traversal and per-step state recording.
- [ ] M2A.3 Stop at Approval before the first write.
- [ ] M2A.4 Persist the paused run and resume the same run after approval.
- [ ] M2A.5 Never repeat completed actions during resume or retry.
- [ ] M2A.6 Record connector evidence, errors, approval, and artifacts in the
  trace.
- [ ] M2A.7 Provide a replay/read path for a completed or prerecorded run.

## Milestone 2B — Compiler, validator, connectors, and tests

Owner: junior developer 1. Details: `tasks/JUNIOR_COMPILER_VALIDATOR.md`.

- [ ] M2B.1 Compile the fixed meeting-prep intent into allowlisted typed blocks.
- [ ] M2B.2 Provide a clearly labeled deterministic seeded fallback.
- [ ] M2B.3 Reject unsupported tools and malformed workflow output.
- [ ] M2B.4 Validate fields, ports, reachability, cycles, connectors, and
  approval placement.
- [ ] M2B.5 Implement bounded Calendar read access.
- [ ] M2B.6 Implement dedicated-vault Obsidian search and idempotent write
  adapters.
- [ ] M2B.7 Add compiler, validator, connector, and idempotency tests.

## Milestone 2C — One-screen client

Owner: junior developer 2. Details: `tasks/JUNIOR_CLIENT.md`.

- [ ] M2C.1 Render the fixed workflow from `DemoState`.
- [ ] M2C.2 Show the block library, workflow, inspector, and bottom trace.
- [ ] M2C.3 Allow a meaningful Approval reorder using the frozen mutation
  contract.
- [ ] M2C.4 Display deterministic validation feedback.
- [ ] M2C.5 Render idle, running, awaiting-approval, completed, and error states.
- [ ] M2C.6 Show connector evidence, approval details, and the final artifact.
- [ ] M2C.7 Add relevant client checks without adding unapproved dependencies.

## Milestone 3 — Integration

- [ ] M3.1 Connect prompt compilation to the stored Jac workflow graph.
- [ ] M3.2 Confirm the UI edit mutates the real stored graph.
- [ ] M3.3 Connect validation results to the UI.
- [ ] M3.4 Connect execution events to the live trace.
- [ ] M3.5 Connect the Approval control to the persisted resume path.
- [ ] M3.6 Connect the final artifact to the result view.
- [ ] M3.7 Run the fixed workflow successfully three consecutive times.
- [ ] M3.8 Verify that retries and resumes never create duplicate brief files.

Acceptance:

- The golden path is live rather than an animation.
- At least one connector call is verifiably live.
- The final file creation is real, bounded, approved, and idempotent.
- DemoState and live runtime state are visually distinguishable.

## Milestone 4 — Verification and hardening

- [ ] M4.1 Run formatter, Jac checks, tests, and the available build.
- [ ] M4.2 Run scenarios for compilation, validation failure, connector failure,
  pause/resume, and idempotent output.
- [ ] M4.3 Perform a clean-clone setup test.
- [ ] M4.4 Scan tracked files and history for credentials and personal data.
- [ ] M4.5 Verify the app never reads a personal calendar or personal vault.
- [ ] M4.6 Verify unsupported actions are absent from blocks and connector APIs.
- [ ] M4.7 Inspect the final diff for scope creep and accidental legacy claims.
- [ ] M4.8 Verify the one-screen demo at the presentation laptop size.

## Milestone 5 — Demo and submission

- [ ] M5.1 Seed the two controlled meetings and vault notes.
- [ ] M5.2 Rehearse the 90-second golden demo.
- [ ] M5.3 Prepare a clearly labeled prerecorded fallback.
- [ ] M5.4 Capture screenshots showing blocks, approval, trace, and artifact.
- [ ] M5.5 Update README with setup, architecture, permissions, demo, tests,
  limitations, and truthful connector status.
- [ ] M5.6 Draft the Agentic AI submission without unverified claims.
- [ ] M5.7 Verify repository, video, and submission links while logged out.

## Failure cuts

Cut in this order if time slips:

1. Notion or any third connector.
2. Packaged Tauri/macOS wrapper.
3. Free-form generation beyond the fixed typed intent.
4. Animations, zoom, and free-form canvas positioning.
5. Workflow saving and replay.

Never cut:

- the real Jac graph
- the meaningful user edit
- deterministic validation
- one bounded live connector
- approval pause/resume
- the created artifact
- the readable trace

## Final definition of done

- [ ] All judged code was created within organizer rules.
- [ ] Jac owns the working graph and walkers.
- [ ] A fresh clone can start the documented core workflow.
- [ ] The fixed prompt produces the expected editable graph.
- [ ] Moving Approval changes stored graph order and validation.
- [ ] Controlled Calendar events are retrieved live or the fallback is labeled.
- [ ] Controlled Obsidian notes are retrieved and exactly one brief is written.
- [ ] Execution pauses and resumes the same persisted run.
- [ ] Completed steps are not repeated.
- [ ] The brief cites matched records and marks missing context.
- [ ] The trace shows steps, evidence, approval, errors, and artifact.
- [ ] Required scenario tests pass.
- [ ] No secret or personal data appears in the repository or recording.
- [ ] Public submission links work while logged out.
