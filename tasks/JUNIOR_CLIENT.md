# Junior Developer 2 — One-Screen Client

## Start gate

Before editing:

1. Read `AGENTS.md` and `TASKS.md`.
2. Confirm the contract-freeze gate is **OPEN**.
3. Confirm the frozen `DemoState`, workflow view model, mutation contract, event
   schema, validation result, approval state, and artifact shape exist.

If any requirement is missing, do not invent a backend or schema. Report:

`WAITING_FOR_FROZEN_CONTRACTS`

## Exclusive ownership

Own only the established equivalents of:

- `client/canvas.cl.jac`
- `client/components.cl.jac`
- other client-only files approved by the main developer
- client-focused tests

Do not edit contracts, graph schema, runtime, connectors, `main.jac`, package
configuration, or `TASKS.md`.

## Layout tasks

- [ ] Build one screen; do not add a landing page or app shell suite.
- [ ] Left: small library for Trigger, Connector, Agent, Approval, Output, and
  Utility blocks.
- [ ] Center: readable vertical workflow with visible connections.
- [ ] Right: selected-block inputs, outputs, connector, permissions, validation,
  and Run/Dry Run control.
- [ ] Bottom: collapsible trace with status, duration, connector evidence,
  errors, approval, and artifacts.
- [ ] Keep the working flow visible at presentation-laptop size.

## Interaction tasks

- [ ] Render the fixed seven-block workflow from `DemoState`.
- [ ] Provide the frozen control for moving Approval before Save Brief.
- [ ] Show that the edit changes workflow order and validation.
- [ ] Render idle, validating, running, awaiting-approval, completed, and error
  states.
- [ ] Provide an explicit Approve action displaying exactly what will be
  written.
- [ ] Resume the same visible run after approval.
- [ ] Reveal `Tomorrow Brief.md` in the final artifact view.
- [ ] Keep fixture state visibly distinguishable from live runtime state.

## Presentation rules

- [ ] Neutral colors before execution.
- [ ] Blue only for the active step.
- [ ] Green only for completed steps.
- [ ] Amber for approval.
- [ ] Red only for real validation or runtime errors.
- [ ] Use large readable labels, visible focus, and keyboard-accessible controls.
- [ ] Prefer reliable move-up/move-down or constrained reorder controls if
  free-form dragging is unstable.
- [ ] Keep animation secondary to state clarity and demo reliability.

## Explicit exclusions

- No authentication, onboarding, marketplace, billing, settings suite, or
  additional pages.
- No Notion or third connector.
- No arbitrary shell, Terminal, browser, mouse, or keyboard blocks.
- No client-side fake success presented as live execution.
- No competing graph schema or runtime.
- No unapproved dependencies.

## Client checks

- [ ] Fixed workflow renders in the expected order.
- [ ] Approval reorder calls the frozen mutation contract.
- [ ] Every validation state renders correctly.
- [ ] Every run state renders correctly.
- [ ] Connector evidence and errors are readable.
- [ ] Approval details and artifact are readable.
- [ ] Keyboard and focus behavior work for the golden path.
- [ ] The final presentation-sized layout does not clip essential proof.

## Completion

- Run the relevant formatter, client checks, tests, and build.
- Inspect the final diff for contract drift and scope growth.
- Do not commit or push.
- Return `tasks/HANDOFF_TEMPLATE.md` with exact command results and risks.
