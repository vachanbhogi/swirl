# AGENTS.md — QuaZe Engineering Contract

## Product

QuaZe is a prompt-first agentic workflow builder for non-technical users. A
person describes an outcome in plain language, then inspects, edits, validates,
approves, runs, and audits the generated Jac graph without writing code.

The current engineering scope proves that product through one narrow,
local-first macOS meeting-prep workflow:

> prompt -> editable Jac graph -> validation -> Calendar + Obsidian retrieval
> -> draft -> approval pause -> saved brief -> visible trace

The golden workflow contains exactly these blocks, in order: Run Now, Read
Calendar, Search Vault, Draft Brief, Approval, Save Brief, Open Result.

Do not confuse product direction with implemented capability. This build
supports only the seven golden block types. Additional workflow types require
explicitly implemented and reviewed blocks, connectors, validation rules, and
tests.

The graph, run lifecycle, approval pause/resume, evidence, and artifact state
live in Jac. The client is written with Jac's full-stack client support. Do not
introduce a separate frontend application or a parallel API layer.

## Engineering Method

- Inspect relevant code and instructions before editing.
- Preserve unrelated changes and stay within assigned file ownership.
- Prefer the smallest coherent change that fixes the root cause.
- Keep types strict and failures explicit. Do not add unsafe casts, broad
  exception handling, silent fallbacks, or secrets.
- Do not add a production dependency, public API, schema, or persistent-data
  change without the integration lead's approval.
- Add or update tests when behavior changes.
- Run relevant checks and inspect the final diff before handing work off.
- Never claim a check, connector, permission, or live integration worked unless
  it was actually exercised.

## Architecture

Shared view contracts:

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

Persistent Jac graph entities:

- `Workflow`
- `Block`
- `Run`
- `RunStep`
- `Approval`
- `Artifact`
- `AgentEvent`

Typed graph edges:

- `ContainsBlock` and `ExecutionFlow`
- `HasRun`, `HasStep`, and `StepForBlock`
- `RequiresApproval`
- `HasEvidence`
- `ProducedArtifact` and `CitesEvidence`

Public walkers:

- `compile_prompt`
- `validate_workflow`
- `reorder_blocks`
- `start_run`
- `approve_run`
- `get_run`

The integration lead owns `contracts.sv.jac`, the public walker signatures, and
schema changes. Parallel agents must request contract changes rather than
editing these boundaries.

## Execution Rules

- The allowlist is limited to the seven golden block types.
- Prompt compilation may use hosted `by llm()` only when configured through the
  environment. The deterministic golden compiler must work without credentials
  and must label when it is used.
- Validation rejects missing inputs, unsupported block types, cycles,
  unreachable steps, unavailable connectors, and a write not immediately
  preceded by Approval.
- A run records a step's completion before advancing.
- Approval pauses before Save Brief. Approval resumes the same persisted run
  without repeating completed steps.
- `Tomorrow Brief.md` is idempotent across resume and retry.
- Calendar access is read-only and limited to the configured dedicated demo
  calendar.
- Vault access is path-contained inside the dedicated demo vault.

## Safety and Claims

- Never access personal calendars or vaults.
- Never write to Calendar.
- Never run arbitrary shell commands from workflow input.
- Never store API keys, model credentials, tokens, or personal data.
- Do not claim local inference when a hosted compiler is configured.
- Distinguish fixture, fallback, unavailable, and live connector behavior in
  state, logs, docs, and demo copy.
- Opening Obsidian and reading Calendar require macOS permissions and must be
  verified on the demo machine.

## Parallel Work

Read `AGENT_HANDOFF.md` before starting. Work only in the assigned worktree and
owned files. Do not merge or push an agent branch. Return the commit hash,
changed files, commands and results, one risk, and any contract request to the
integration lead.

## Required Checks

```bash
jac check .
jac test
jac build --client web
```

Run focused tests during development. The full suite and production client
build are integration gates.
