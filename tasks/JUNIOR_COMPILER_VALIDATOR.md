# Junior Developer 1 — Compiler, Validator, Connectors, and Tests

## Start gate

Before editing:

1. Read `AGENTS.md` and `TASKS.md`.
2. Confirm the contract-freeze gate is **OPEN**.
3. Confirm the frozen workflow, block, connector, run, event, approval, artifact,
   and fixture definitions exist.

If any requirement is missing, do not create replacement contracts. Report:

`WAITING_FOR_FROZEN_CONTRACTS`

## Exclusive ownership

Own only the established equivalents of:

- `agents/compiler.jac`
- `runtime/validator.jac`
- `connectors/calendar.jac`
- `connectors/obsidian.jac`
- compiler, validator, and connector-focused tests

Do not edit shared contracts, the executor, `main.jac`, client code, package
configuration, or `TASKS.md`.

## Compiler tasks

- [ ] Accept only the bounded meeting-prep intent supported by the product.
- [ ] Produce typed output that conforms exactly to the frozen `WorkflowSpec`.
- [ ] Map output only to the seven allowlisted block kinds.
- [ ] Reject invented connectors, tools, permissions, block kinds, and ports.
- [ ] Return explicit errors for malformed or unsupported requests.
- [ ] Implement a clearly labeled seeded typed fallback for demo reliability.
- [ ] Keep model interpretation separate from deterministic schema validation.

## Validator tasks

- [ ] Validate required fields and stable IDs.
- [ ] Validate typed input/output port compatibility.
- [ ] Validate connector availability and declared permissions.
- [ ] Detect cycles and unreachable blocks.
- [ ] Require exactly one reachable start and terminal result path.
- [ ] Require Approval before every write-capable block.
- [ ] Reject write, send, delete, move, purchase, publish, shell, Terminal,
  browser, mouse, and keyboard capabilities outside the allowlist.
- [ ] Return frozen error codes and target block IDs for client display.
- [ ] Keep validation deterministic and independent of model calls.

## Calendar connector tasks

- [ ] Read only the controlled upcoming meeting set.
- [ ] Return only fields required by the meeting brief.
- [ ] Never create, modify, or delete calendar events.
- [ ] Return explicit unavailable/authentication/permission errors.
- [ ] Provide a labeled fixture adapter without pretending it is live MCP.

## Obsidian connector tasks

- [ ] Resolve and validate the dedicated demo-vault root.
- [ ] Reject paths outside that root.
- [ ] Match the controlled notes deterministically by people/project metadata.
- [ ] Ignore the deliberately irrelevant note.
- [ ] Write only the approved `Tomorrow Brief.md` output.
- [ ] Use an artifact/idempotency key to prevent duplicate output.
- [ ] Return explicit errors without silently falling back to personal data.

## Tests

- [ ] Valid fixed-prompt compilation.
- [ ] Seeded fallback output.
- [ ] Unsupported tool rejection.
- [ ] Missing Approval rejection.
- [ ] Incompatible ports and missing fields.
- [ ] Cycle and unreachable-node detection.
- [ ] Unavailable connector behavior.
- [ ] Vault path-escape rejection.
- [ ] Connector failure propagation.
- [ ] Duplicate-write prevention.

## Completion

- Run the relevant Jac checks and tests.
- Inspect the final diff for contract drift and unsafe permissions.
- Do not commit or push.
- Return `tasks/HANDOFF_TEMPLATE.md` with exact command results and risks.
