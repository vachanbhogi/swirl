# Main Developer Tasks

The main developer owns architecture, frozen contracts, the Jac graph and
execution lifecycle, integration, and final verification.

## Exclusive files

The final layout may be adjusted after Jac toolchain verification, but the main
developer exclusively owns the equivalents of:

- `main.jac`
- `workflow/schema.jac`
- `workflow/library.jac`
- `runtime/executor.jac`
- shared contract and fixture definitions
- integration adapters at client/runtime boundaries
- `TASKS.md`

## Phase A — Establish truth

- [ ] Inspect every current file and classify it as reusable, stale, or unsafe.
- [ ] Verify the installed Jac CLI and the syntax supported by `jac.toml`.
- [ ] Check current official Jac documentation before choosing project and
  client structure.
- [ ] Replace the stale Swirl identity and broad automation plan with QuaZe.
- [ ] Convert all unverified success claims into honest pending work.
- [ ] Record verified setup and check commands.

## Phase B — Freeze contracts

- [ ] Define the allowlisted block kinds:
  `run_now`, `read_calendar`, `search_obsidian`, `draft_brief`, `approval`,
  `save_brief`, and `open_result`.
- [ ] Define stable IDs, typed inputs/outputs, permissions, connector names, and
  completion states for every block.
- [ ] Define workflow, connector, run, event, approval, and artifact types.
- [ ] Define deterministic validation and error codes.
- [ ] Define the client mutation for moving Approval before Save Brief.
- [ ] Define the two demo meetings, matching notes, irrelevant note, expected
  brief, and bounded output location.
- [ ] Add contract tests or executable examples where the Jac toolchain allows.
- [ ] Review the contract with both junior ownership areas.
- [ ] Open the contract-freeze gate in `TASKS.md`.

## Phase C — Jac-native runtime

- [ ] Materialize workflows as Jac nodes and edges rather than JSON-only state.
- [ ] Implement an execution walker that records a step before advancing.
- [ ] Enforce validation before any connector execution.
- [ ] Persist state needed to pause at Approval.
- [ ] Resume the same run without repeating completed steps.
- [ ] Record artifact IDs before advancing past a write.
- [ ] Expose a read/replay path for trace rendering and fallback demonstration.
- [ ] Keep connector calls behind the frozen allowlisted interface.

## Phase D — Integrate junior work

- [ ] Review every junior handoff before modifying their files.
- [ ] Confirm compiler output conforms exactly to the frozen schema.
- [ ] Confirm validator results and error codes match client expectations.
- [ ] Confirm connectors cannot escape demo boundaries.
- [ ] Connect client mutations to real graph mutations.
- [ ] Connect runtime events to the client trace.
- [ ] Connect approval to persisted resume.
- [ ] Connect the artifact to the result view.
- [ ] Resolve mismatches at integration boundaries without silently changing
  frozen contracts.

## Phase E — Verify and hand off

- [ ] Run all available formatting, checks, tests, and builds.
- [ ] Run the fixed workflow three times.
- [ ] Verify connector failure and approval-resume recovery.
- [ ] Verify output idempotency.
- [ ] Perform clean-clone and secret checks.
- [ ] Review the final diff and repository claims.
- [ ] Update `TASKS.md` only with checks that actually passed.

## Main developer handoff

Use `tasks/HANDOFF_TEMPLATE.md`. State separately:

- verified live behavior
- fixture-only behavior
- experimental behavior
- unavailable behavior
- any physical-Mac or organizer verification still required
