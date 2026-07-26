# QuaZe Product Requirements

## Product Thesis

Building an agentic workflow normally requires code, API knowledge, connector
configuration, and trust in a largely invisible execution path. QuaZe lets a
non-technical user describe an outcome in one prompt and receive an
inspectable Jac workflow they can understand, edit, validate, approve, run, and
audit.

The product direction is prompt-to-agentic-workflow creation. The current MVP
is intentionally narrower: one meeting-preparation workflow proves the shared
graph, validation, execution, approval, evidence, and artifact lifecycle before
additional trusted blocks and connectors are added.

## Current MVP Boundary

Preparing for tomorrow's meetings means jumping between Calendar, scattered
notes, and a blank document. QuaZe's first supported workflow gathers only the
needed context, drafts a cited brief, waits for human approval, and saves the
approved result to a dedicated Obsidian vault.

This build is not a general desktop automation platform. It does not yet
generate arbitrary workflows, send email, modify calendars, browse arbitrary
files, or execute arbitrary commands. Product direction must not be presented
as implemented capability.

## Golden Demo

The user enters:

> Prepare me for tomorrow's meetings using my QuaZe Demo calendar and demo
> Obsidian vault. Draft a cited brief, ask before saving it, then open it.

QuaZe compiles or deterministically falls back to this editable seven-block
graph:

1. Run Now
2. Read Calendar
3. Search Vault
4. Draft Brief
5. Approval
6. Save Brief
7. Open Result

The user can reorder the plan, validate it, start it, inspect connector
evidence, approve the draft, and reveal `Tomorrow Brief.md`. The execution spine
shows the persisted status of each Jac graph step.

## Required Behavior

### Compile

- A typed hosted-model compiler may be enabled through environment
  configuration.
- Output is restricted to the seven supported block types.
- Missing configuration, network failure, parsing failure, or invalid model
  output activates the labeled deterministic golden compiler.
- No credentials are stored in the repository.

### Validate

Validation is deterministic and rejects:

- unsupported block types
- missing required inputs
- cycles
- unreachable steps
- unavailable required connectors
- any write step without Approval immediately before it

### Execute

- A persisted `Run` and ordered `RunStep` graph is created before execution.
- Each completed step is recorded before the walker advances.
- A connector failure fails the run, exposes evidence, and creates no artifact.
- Approval pauses before the write.
- Approval or rejection targets the same persisted run.
- Resume skips completed steps.
- Retry or repeated approval creates exactly one artifact.

### Retrieve

- Calendar reads a bounded tomorrow window from a dedicated `QuaZe Demo`
  calendar and never modifies Calendar.
- Vault search is limited to a dedicated Markdown demo vault.
- The filesystem MCP server is restricted to that vault.
- Fixture mode is available and visibly labeled; it is not presented as live
  Calendar or MCP evidence.

### Draft and Save

- The fixture includes `Apex design review`, `Maya onboarding`, two matching
  notes, and one irrelevant note.
- The draft cites matched meeting and note records.
- The irrelevant note is excluded.
- Missing context is stated, not invented.
- Save creates or updates one `Tomorrow Brief.md` artifact idempotently.
- Open Result opens the saved file in Obsidian when available and reports a
  clear unavailable state otherwise.

## Interface

One Jac client screen contains:

- prompt and compile state
- seven-block library
- editable vertical execution spine
- selected-block inspector
- validation results
- run control and approval panel
- live/polled trace
- artifact path, hash, and reveal action

Move-up and move-down controls are required. Drag-and-drop is optional. Status
colors are neutral for pending, blue for running, green for succeeded, amber
for approval, and red for failed or invalid.

## Acceptance

- [ ] Golden prompt produces only supported blocks.
- [ ] Unsupported intent fails or uses a labeled deterministic fallback.
- [ ] Moving Approval away from Save Brief fails validation.
- [ ] Connector failure creates no output.
- [ ] Approval pauses before Save Brief.
- [ ] Approval resumes the same run without repeating completed steps.
- [ ] Repeated resume/retry produces exactly one artifact.
- [ ] Brief cites both matched records and excludes the irrelevant note.
- [ ] Missing context is marked explicitly.
- [ ] Dedicated live Calendar evidence is visible.
- [ ] Dedicated-vault MCP evidence is visible.
- [ ] UI trace matches persisted Jac state.
- [ ] Fresh-clone commands require no personal data or repository secret.

## Out of Scope

- arbitrary workflow generation beyond the allowlisted meeting-prep blocks
- unreviewed or user-defined executable block types
- production OAuth or authentication
- email sending
- Calendar modification
- personal vault access
- arbitrary shell or AppleScript blocks
- unrestricted computer control
- billing, marketplace, or team accounts
- desktop packaging before the golden web flow is stable
