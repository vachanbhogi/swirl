# QuaZe Engineering and Agent Coordination

## Product authority

QuaZe is the current product name. The authoritative product direction is the
current `JacHacks SF — QuaZe Winning Plan` Google Doc and `TASKS.md`.

Some checked-in files still describe an earlier product named Swirl. Treat
those files as unverified legacy material to reconcile, not as proof of
implemented behavior or as permission to broaden QuaZe's scope.

QuaZe's hackathon loop is:

> prompt -> blocks -> edit -> validate -> run -> approve -> artifact -> trace

The fixed demo prepares a meeting brief from bounded Calendar reads and a
dedicated Obsidian demo vault. Jac must own the workflow graph, validation,
execution state, approval pause/resume, and trace. Jac may not be a thin wrapper
around a separate workflow engine.

## Working method

- Inspect the repository and your assigned task file before editing.
- Follow existing patterns only when they agree with the current QuaZe plan.
- Make a short plan, implement the assigned scope, run relevant checks, and
  inspect the final diff.
- Preserve unrelated work and never discard another agent's changes.
- Keep types strict, failures explicit, and connector permissions bounded.
- Do not add a production dependency or change a frozen contract without the
  main developer's approval.
- Do not commit, push, deploy, publish, or submit unless the user explicitly
  asks.
- Never claim a feature or check works unless it was run and verified.

## Safety boundaries

- Default connector behavior to read-only.
- Require an explicit Approval block before any write.
- Do not expose arbitrary shell, Terminal, browser, mouse, keyboard, deletion,
  sending, purchasing, or publishing actions.
- Keep credentials, personal calendar data, and personal vault data out of the
  graph, repository, fixtures, logs, screenshots, and recordings.
- Restrict Obsidian access to the dedicated demo directory.
- Make output writes idempotent so resume or retry cannot duplicate artifacts.

## Ownership

| Role | Task file | Exclusive ownership |
| --- | --- | --- |
| Main developer | `tasks/MAIN_DEVELOPER.md` | Architecture, frozen contracts, Jac graph schema, execution lifecycle, integration, final verification |
| Junior developer 1 | `tasks/JUNIOR_COMPILER_VALIDATOR.md` | Compiler, deterministic validator, bounded connectors, focused tests |
| Junior developer 2 | `tasks/JUNIOR_CLIENT.md` | One-screen client built against the frozen UI contract and DemoState |

No agent may edit another role's exclusive files without approval from the main
developer. The main developer owns `TASKS.md` status updates.

## Start gate

Junior agents must not invent schemas or scaffold competing architecture.
Before editing, they must confirm that the contract-freeze gate in `TASKS.md`
is open and that the contract files named in their task file exist. If the gate
is closed, they should inspect only and report `WAITING_FOR_FROZEN_CONTRACTS`.

## Handoff

Every agent handoff must use `tasks/HANDOFF_TEMPLATE.md` and include:

- files changed
- behavior implemented
- exact checks and results
- assumptions and unverified behavior
- risks and integration requests
