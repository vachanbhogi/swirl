"""QuaZe prompt-first meeting-prep workflow client."""

import "./styles.css";

sv import from contracts {
    AgentEventSpec,
    BlockSpec,
    DemoState,
    RunState,
    RunStepSpec,
    StepState
}
sv import from endpoints {
    approve_run,
    compile_prompt,
    get_run,
    recover_run,
    reorder_blocks,
    start_run,
    validate_workflow
}

def run_state_label(state: RunState) -> str {
    value = str(state);
    if value == "running" {
        return "running";
    }
    if value == "awaiting_approval" {
        return "awaiting approval";
    }
    if value == "succeeded" {
        return "succeeded";
    }
    if value == "failed" {
        return "failed";
    }
    if value == "canceled" {
        return "canceled";
    }
    return "idle";
}

def run_state_class(state: RunState) -> str {
    value = str(state);
    if value == "running" {
        return "status-running";
    }
    if value == "awaiting_approval" {
        return "status-awaiting";
    }
    if value == "succeeded" {
        return "status-succeeded";
    }
    if value == "failed" {
        return "status-failed";
    }
    if value == "canceled" {
        return "status-canceled";
    }
    return "status-idle";
}

def step_state_label(state: StepState | None) -> str {
    value = "pending" if state is None else str(state);
    if value == "running" {
        return "running";
    }
    if value == "awaiting_approval" {
        return "awaiting approval";
    }
    if value == "succeeded" {
        return "succeeded";
    }
    if value == "skipped" {
        return "skipped";
    }
    if value == "failed" {
        return "failed";
    }
    if value == "canceled" {
        return "canceled";
    }
    return "pending";
}

def step_state_class(state: StepState | None) -> str {
    value = "pending" if state is None else str(state);
    if value == "running" {
        return "step-running";
    }
    if value == "awaiting_approval" {
        return "step-awaiting";
    }
    if value == "succeeded" {
        return "step-succeeded";
    }
    if value == "skipped" {
        return "step-skipped";
    }
    if value == "failed" {
        return "step-failed";
    }
    if value == "canceled" {
        return "step-canceled";
    }
    return "step-pending";
}

def selected_class(selected: bool) -> str {
    if selected {
        return " is-selected";
    }
    return "";
}

def validation_class(valid: bool) -> str {
    if valid {
        return "validation-panel validation-valid";
    }
    return "validation-panel validation-invalid";
}

def compiler_tone(mode: str) -> str {
    if mode == "deterministic" {
        return "blue";
    }
    return "neutral";
}

def step_for_block(steps: list[RunStepSpec], block_id: str) -> RunStepSpec | None {
    for step in steps {
        if step.block_id == block_id {
            return step;
        }
    }
    return None;
}

def events_for_block(
    events: list[AgentEventSpec], block_id: str
) -> list[AgentEventSpec] {
    return [
        event
        for event in events
        if event.block_id == block_id
    ];
}

def ModeLabel(label: str, value: str, tone: str = "neutral") -> JsxElement {
    return
        <span className={"mode-label mode-" + tone}>
            <span>{label}</span>
            <strong>{value}</strong>
        </span>;
}

def BlockLibrary(blocks: list[BlockSpec]) -> JsxElement {
    return
        <section className="quiet-panel library-panel" aria-labelledby="library-title">
            <div className="section-heading">
                <div>
                    <p className="eyebrow">Allowlist</p>
                    <h2 id="library-title">Block library</h2>
                </div>
                <span className="count-label">{str(len(blocks))} / 7</span>
            </div>
            <p className="section-note">
                This workflow can use only these meeting-prep actions.
            </p>
            <ol className="library-list">
                {[
                    <li key={block.id}>
                        <span className="library-index">{str(index + 1).zfill(2)}</span>
                        <span>
                            <strong>{block.title}</strong>
                            <small>{block.block_type.replace("_", " ")}</small>
                        </span>
                    </li> for index in range(len(blocks)) for block in [blocks[index]]
                ]}
            </ol>
        </section>;
}

def ExecutionSpine(
    demo: DemoState,
    selected_block_id: str,
    busy: bool,
    on_select: Callable[[str], None],
    on_move: Callable[[str, str], None]
) -> JsxElement {
    return
        <section className="spine-panel" aria-labelledby="spine-title">
            <div className="section-heading spine-heading">
                <div>
                    <p className="eyebrow">Editable Jac graph</p>
                    <h2 id="spine-title">Execution spine</h2>
                </div>
                <span className={"run-state " + run_state_class(demo.run_state)}>
                    <span className="status-dot"></span>
                    {run_state_label(demo.run_state)}
                </span>
            </div>
            <p className="section-note">
                Select a step to inspect it. Order changes are checked on the server.
            </p>
            <ol className="execution-spine">
                {[
                    <li
                        key={block.id}
                        className={f"spine-step {step_state_class(
                            step.state if step is not None else None
                        )}{selected_class(selected_block_id == block.id)}"}
                    >
                        <button
                            type="button"
                            className="step-select"
                            aria-label={"Inspect " + block.title}
                            aria-pressed={selected_block_id == block.id}
                            onClick={lambda { on_select(block.id); }}
                        >
                            <span className="step-node">{str(index + 1).zfill(2)}</span>
                            <span className="step-copy">
                                <span className="step-title-line">
                                    <strong>{block.title}</strong>
                                    <span className="step-status">
                                        {step_state_label(
                                            step.state
                                                if step is not None
                                                else None
                                        )}
                                    </span>
                                </span>
                                <span className="step-type">
                                    {block.block_type.replace("_", " ")}
                                </span>
                                {step is not None
                                and step.evidence_summary != ""
                                and <span className="step-evidence">
                                    {step.evidence_summary}
                                </span>
                                or None}
                                {step is not None
                                and step.error != ""
                                and <span className="step-error">{step.error}</span>
                                or None}
                                {len(events_for_block(demo.events, block.id)) > 0
                                and <span className="step-event">
                                    {str(len(events_for_block(demo.events, block.id)))}{" trace " + (
                                        "events"
                                            if len(
                                                events_for_block(demo.events, block.id)
                                            ) != 1
                                            else "event"
                                    )}
                                </span>
                                or None}
                            </span>
                        </button>
                        <span
                            className="move-controls"
                            aria-label={"Move " + block.title}
                        >
                            <button
                                type="button"
                                disabled={busy or index == 0}
                                aria-label={"Move " + block.title + " up"}
                                title="Move up"
                                onClick={lambda { on_move(block.id, "up"); }}
                            >
                                ↑
                            </button>
                            <button
                                type="button"
                                disabled={busy
                                or index == len(demo.workflow.blocks) - 1}
                                aria-label={"Move " + block.title + " down"}
                                title="Move down"
                                onClick={lambda { on_move(block.id, "down"); }}
                            >
                                ↓
                            </button>
                        </span>
                    </li> for index in range(len(demo.workflow.blocks))
                    for block in [demo.workflow.blocks[index]]
                    for step in [step_for_block(demo.run_steps, block.id)]
                ]}
            </ol>
        </section>;
}

def BlockInspector(
    block: BlockSpec | None, events: list[AgentEventSpec]
) -> JsxElement {
    if block is None {
        return
            <section className="quiet-panel inspector-panel">
                <p className="eyebrow">Inspector</p>
                <h2>No block selected</h2>
                <p className="empty-guidance">
                    Choose a step in the execution spine to inspect its inputs and permissions.
                </p>
            </section>;
    }

    return
        <section
            className="quiet-panel inspector-panel"
            aria-labelledby="inspector-title"
        >
            <div className="section-heading">
                <div>
                    <p className="eyebrow">Selected block</p>
                    <h2 id="inspector-title">{block.title}</h2>
                </div>
                <span className="mono-tag">{block.block_type}</span>
            </div>
            <dl className="inspector-list">
                <div>
                    <dt>Inputs</dt>
                    <dd>
                        {", ".join(block.inputs) if len(block.inputs) > 0 else "None"}
                    </dd>
                </div>
                <div>
                    <dt>Outputs</dt>
                    <dd>
                        {", ".join(block.outputs) if len(block.outputs) > 0 else "None"}
                    </dd>
                </div>
                <div>
                    <dt>Permissions</dt>
                    <dd>
                        {", ".join(block.permissions)
                            if len(block.permissions) > 0
                            else "None"}
                    </dd>
                </div>
                <div>
                    <dt>Configuration</dt>
                    <dd>{str(block.config) if len(block.config) > 0 else "Default"}</dd>
                </div>
            </dl>
            <div className="trace-detail">
                <div className="subheading-row">
                    <h3>Aligned trace</h3>
                    <span>{str(len(events))}</span>
                </div>
                {len(events) == 0
                and <p className="empty-guidance">
                    Run the workflow to record evidence for this step.
                </p>
                or <ol className="event-list">
                    {[
                        <li key={event.id}>
                            <span className="event-sequence">
                                #{str(event.sequence).zfill(2)}
                            </span>
                            <span>
                                <strong>{event.event_type.replace("_", " ")}</strong>
                                <p>{event.message}</p>
                                {event.created_at != ""
                                and <time>{event.created_at}</time>
                                or None}
                            </span>
                        </li> for event in events
                    ]}
                </ol>}
            </div>
        </section>;
}

def ValidationPanel(demo: DemoState) -> JsxElement {
    return
        <section
            className={validation_class(demo.validation.valid)}
            aria-live="polite"
            aria-labelledby="validation-title"
        >
            <div>
                <p className="eyebrow">Deterministic validation</p>
                <h2 id="validation-title">
                    {demo.validation.valid
                    and "Ready to run"
                    or "Fix the workflow order"}
                </h2>
            </div>
            <div className="validation-copy">
                {demo.validation.valid
                and <p>
                    Seven supported blocks form one reachable path with approval before write.
                </p>
                or (
                    len(demo.validation.errors) > 0
                    and <ul>
                        {[
                            <li key={error}>{error}</li>
                            for error in demo.validation.errors
                        ]}
                    </ul>
                    or <p>Run validation to get the exact graph change required.</p>
                )}{len(demo.validation.warnings) > 0
                and <ul className="warning-list">
                    {[
                        <li key={warning}>{warning}</li>
                        for warning in demo.validation.warnings
                    ]}
                </ul>
                or None}
            </div>
        </section>;
}

def RunContractPanel(demo: DemoState) -> JsxElement {
    contract = demo.run_contract;
    return
        <section className="proof-panel contract-panel" aria-labelledby="contract-title">
            <div className="section-heading">
                <div>
                    <p className="eyebrow">Preview-to-Proof preflight</p>
                    <h2 id="contract-title">Experimental run boundary</h2>
                </div>
                <span className="proof-state">{contract.state}</span>
            </div>
            <p className="effect-counts">
                Reads {str(contract.read_count)} · Transforms {str(contract.transform_count)}
                {" · "}Approvals {str(contract.approval_count)} · Writes {str(contract.write_count)}
                {" · "}Opens {str(contract.open_count)} · Sends {str(contract.send_count)}
                {" · "}Deletes {str(contract.delete_count)} · Purchases {str(contract.purchase_count)}
            </p>
            <dl className="proof-grid">
                <div>
                    <dt>Enforcement</dt>
                    <dd>{contract.enforcement_level}</dd>
                </div>
                <div>
                    <dt>Connector profile</dt>
                    <dd>{contract.connector_mode}</dd>
                </div>
                <div>
                    <dt>Maximum affected</dt>
                    <dd>{str(contract.maximum_affected_items)}</dd>
                </div>
                <div>
                    <dt>Required approvals</dt>
                    <dd>{", ".join(contract.required_approvals)
                        if contract.required_approvals
                        else "None"}</dd>
                </div>
            </dl>
            <div className="visible-blockers" role="note">
                <h3>Experimental blockers</h3>
                <ul className="blocker-list">
                    {[
                        <li key={blocker}>{blocker}</li>
                        for blocker in contract.blockers
                    ]}
                </ul>
            </div>
            <details>
                <summary>Scopes and outbound data</summary>
                <div className="details-body">
                    <h3>Resource scopes</h3>
                    <ul>
                        {[
                            <li key={scope.connector_id + scope.permission}>
                                <strong>{scope.connector_id}</strong>
                                {" · " + scope.access + " · " + scope.mode + " · " + scope.target}
                            </li> for scope in contract.resource_scopes
                        ]}
                    </ul>
                    <h3>Outbound data</h3>
                    {contract.outbound_data
                    and <ul>{[
                        <li key={entry}>{entry}</li> for entry in contract.outbound_data
                    ]}</ul>
                    or <p>None in deterministic fixture execution.</p>}
                </div>
            </details>
        </section>;
}

def EffectProposalPanel(demo: DemoState) -> JsxElement {
    proposal = demo.effect_proposal;
    return
        <section className="proof-panel proposal-panel" aria-labelledby="proposal-title">
            <div className="section-heading">
                <div>
                    <p className="eyebrow">Exact effect proposal</p>
                    <h2 id="proposal-title">
                        {proposal.change_kind.replace("_", " ")
                            if proposal.change_kind != ""
                            else "Not prepared"}
                    </h2>
                </div>
                <span className="proof-state">{proposal.state}</span>
            </div>
            <dl className="proof-grid">
                <div>
                    <dt>Target</dt>
                    <dd>{proposal.target if proposal.target != "" else "Not prepared"}</dd>
                </div>
                <div>
                    <dt>Visibility</dt>
                    <dd>{proposal.content_visibility.replace("_", " ")}</dd>
                </div>
                <div>
                    <dt>Sources</dt>
                    <dd>{str(len(proposal.source_references))}</dd>
                </div>
                <div>
                    <dt>Remaining effects</dt>
                    <dd>{", ".join(proposal.remaining_effects)
                        if proposal.remaining_effects
                        else "None"}</dd>
                </div>
            </dl>
            {demo.approval.stale_reason != ""
            and <p className="review-block" role="status">{demo.approval.stale_reason}</p>
            or None}
            {proposal.blockers
            and <ul className="blocker-list review-block">
                {[<li key={blocker}>{blocker}</li> for blocker in proposal.blockers]}
            </ul>
            or None}
            <div className="exact-review">
                <div>
                    <h3>Full proposed content</h3>
                    <pre
                        className="review-scroll"
                        tabIndex={0}
                    >{proposal.proposed_content_excerpt
                        if proposal.proposed_content_excerpt != ""
                        else "Exact content is unavailable."}</pre>
                </div>
                <div>
                    <h3>Full proposed diff</h3>
                    <pre
                        className="review-scroll"
                        tabIndex={0}
                    >{proposal.diff_excerpt
                        if proposal.diff_excerpt != ""
                        else "Exact diff is unavailable."}</pre>
                </div>
            </div>
            <div className="source-list">
                <h3>Sources</h3>
                {proposal.source_references
                and <ul>{[
                    <li key={source}><code>{source}</code></li>
                    for source in proposal.source_references
                ]}</ul>
                or <p>No public source references are available.</p>}
            </div>
            <details>
                <summary>Technical digest details</summary>
                <dl className="technical-grid">
                    <div><dt>Effect digest</dt><dd>{proposal.effect_digest}</dd></div>
                    <div><dt>Approval nonce</dt><dd>{proposal.approval_nonce}</dd></div>
                    <div><dt>Source hash</dt><dd>{proposal.source_references_hash}</dd></div>
                    <div><dt>Prior hash</dt><dd>{proposal.prior_target_hash}</dd></div>
                    <div><dt>Proposed hash</dt><dd>{proposal.proposed_payload_hash}</dd></div>
                </dl>
            </details>
        </section>;
}

def ApprovalPanel(
    demo: DemoState,
    busy: bool,
    uncertain: bool,
    can_approve: bool,
    can_reject: bool,
    on_decide: Callable[[bool], None],
    on_refresh: Callable[[], None]
) -> JsxElement {
    return
        <section className="approval-panel" aria-labelledby="approval-title">
            <div>
                <p className="eyebrow">Human checkpoint</p>
                <h2 id="approval-title">Review before QuaZe writes</h2>
                <p>
                    {demo.approval.prompt
                        if demo.approval.prompt != ""
                        else "Approve the drafted meeting brief before Save Brief runs."}
                </p>
                {uncertain
                and <p className="review-block" role="alert">
                    Decision delivery is uncertain. Refresh persisted state before deciding again.
                </p>
                or None}
            </div>
            <div className="approval-actions">
                {uncertain
                and <button
                    type="button"
                    className="button button-secondary"
                    disabled={busy}
                    onClick={on_refresh}
                >
                    Refresh persisted state
                </button>
                or None}
                <button
                    type="button"
                    className="button button-secondary button-danger"
                    disabled={busy or uncertain or not can_reject}
                    onClick={lambda { on_decide(False); }}
                >
                    Reject &amp; stop
                </button>
                <button
                    type="button"
                    className="button button-approval"
                    disabled={busy or uncertain or not can_approve}
                    onClick={lambda { on_decide(True); }}
                >
                    Approve exact change
                </button>
            </div>
        </section>;
}

def ArtifactPanel(demo: DemoState) -> JsxElement {
    if demo.artifact.path == "" {
        return
            <section
                className="artifact-panel artifact-empty"
                aria-labelledby="artifact-title"
            >
                <div>
                    <p className="eyebrow">Saved brief</p>
                    <h2 id="artifact-title">No artifact yet</h2>
                </div>
                <p>
                    Run the valid workflow, review the draft, and approve it to create Tomorrow Brief.md.
                </p>
            </section>;
    }

    open_step = step_for_block(demo.run_steps, "open-result");
    return
        <section className="artifact-panel" aria-labelledby="artifact-title">
            <div className="artifact-heading">
                <div>
                    <p className="eyebrow">Saved brief</p>
                    <h2 id="artifact-title">Tomorrow Brief.md</h2>
                </div>
                <span className="artifact-state">
                    {demo.artifact.state.replace("_", " ")}
                </span>
            </div>
            <dl className="artifact-grid">
                <div>
                    <dt>Path</dt>
                    <dd>{demo.artifact.path}</dd>
                </div>
                <div>
                    <dt>Content hash</dt>
                    <dd>
                        {demo.artifact.content_hash
                            if demo.artifact.content_hash != ""
                            else "Pending"}
                    </dd>
                </div>
                <div>
                    <dt>Reveal state</dt>
                    <dd>
                        {step_state_label(open_step.state)
                            if open_step is not None
                            else "pending"}
                    </dd>
                </div>
                <div>
                    <dt>Sources</dt>
                    <dd>
                        {len(demo.artifact.source_references) == 0
                        and "None recorded"
                        or <ul>
                            {[
                                <li key={reference}>{reference}</li>
                                for reference in demo.artifact.source_references
                            ]}
                        </ul>}
                    </dd>
                </div>
            </dl>
        </section>;
}

def ReceiptPanel(demo: DemoState) -> JsxElement {
    receipt = demo.receipt;
    return
        <section className="proof-panel receipt-panel" aria-labelledby="receipt-title">
            <div className="section-heading">
                <div>
                    <p className="eyebrow">Persisted run receipt</p>
                    <h2 id="receipt-title">{receipt.state.replace("_", " ")}</h2>
                </div>
                <span className="proof-state">
                    {receipt.effect_outcome.replace("_", " ")
                        if receipt.effect_outcome != ""
                        else "No effect"}
                </span>
            </div>
            <div className="receipt-columns">
                <div>
                    <h3>Planned</h3>
                    {receipt.planned_effects
                    and <ul>{[
                        <li key={effect}>{effect}</li>
                        for effect in receipt.planned_effects
                    ]}</ul>
                    or <p>Not available yet.</p>}
                </div>
                <div>
                    <h3>Performed</h3>
                    {receipt.performed_effects
                    and <ul>{[
                        <li key={effect}>{effect}</li>
                        for effect in receipt.performed_effects
                    ]}</ul>
                    or <p>No effects recorded.</p>}
                </div>
            </div>
            <dl className="proof-grid">
                <div>
                    <dt>Open Result</dt>
                    <dd>{receipt.open_disposition.replace("_", " ")}</dd>
                </div>
                <div>
                    <dt>Retries</dt>
                    <dd>{str(receipt.retry_count)}</dd>
                </div>
                <div>
                    <dt>Duplicate state</dt>
                    <dd>{receipt.duplicate_protection_state.replace("_", " ")}</dd>
                </div>
                <div>
                    <dt>Compiler origin</dt>
                    <dd>{receipt.compiler_provenance.mode}</dd>
                </div>
                <div>
                    <dt>Artifact</dt>
                    <dd>{receipt.artifact_path if receipt.artifact_path != "" else "None"}</dd>
                </div>
                <div>
                    <dt>Artifact hash</dt>
                    <dd>{receipt.artifact_hash if receipt.artifact_hash != "" else "None"}</dd>
                </div>
            </dl>
            {receipt.open_reason != ""
            and <p className="receipt-note">{receipt.open_reason}</p>
            or None}
            <div className="receipt-columns">
                <div>
                    <h3>Sources</h3>
                    {receipt.source_references
                    and <ul>{[
                        <li key={source}><code>{source}</code></li>
                        for source in receipt.source_references
                    ]}</ul>
                    or <p>None recorded.</p>}
                </div>
                <div>
                    <h3>Deviations</h3>
                    {receipt.deviations
                    and <ul className="blocker-list">{[
                        <li key={deviation}>{deviation}</li>
                        for deviation in receipt.deviations
                    ]}</ul>
                    or <p>None.</p>}
                </div>
            </div>
        </section>;
}

def:pub app -> JsxElement {
    has prompt: str = (
        "Prepare me for tomorrow's meetings using the dedicated QuaZe demo "
        "calendar and demo vault. Draft one brief, pause for approval, save "
        "Tomorrow Brief.md, then open it."
    ),
        demo: DemoState | None = None,
        selected_block_id: str = "",
        connector_mode: str = "fixture",
        pending_action: str = "",
        error_message: str = "",
        approval_uncertain: bool = False,
        request_epoch: int = 0;

    def accept_demo(next_demo: DemoState, epoch: int) -> None {
        if epoch != request_epoch {
            return;
        }
        demo = next_demo;
        error_message = "";
        selected_exists = False;
        for block in next_demo.workflow.blocks {
            if block.id == selected_block_id {
                selected_exists = True;
            }
        }
        if not selected_exists and len(next_demo.workflow.blocks) > 0 {
            selected_block_id = next_demo.workflow.blocks[0].id;
        }
    }

    async def compile_workflow -> None {
        if pending_action != "" or prompt.strip() == "" {
            return;
        }
        if (
            demo is not None
            and (
                str(demo.run_state) == "running"
                or str(demo.run_state) == "awaiting_approval"
            )
        ) {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "compile";
        error_message = "";
        try {
            response = root spawn compile_prompt(prompt=prompt);
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "Compile returned no workflow. Check the prompt and try again.";
            }
        } except Exception as _error {
            error_message = "Compile could not reach the Jac runtime. Start the app and try again.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def validate_current -> None {
        if pending_action != "" or demo is None {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "validate";
        error_message = "";
        try {
            response = root spawn validate_workflow(workflow=demo.workflow);
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "Validation returned no result. Keep the graph unchanged and retry.";
            }
        } except Exception as _error {
            error_message = "Validation could not reach the Jac runtime. Retry before running.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def move_block(block_id: str, direction: str) -> None {
        if pending_action != "" or demo is None {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "reorder";
        error_message = "";
        try {
            response = root spawn reorder_blocks(
                workflow=demo.workflow, block_id=block_id, direction=direction
            );
            if response.reports and len(response.reports) > 0 {
                selected_block_id = block_id;
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "The block was not moved. Keep the current order and retry.";
            }
        } except Exception as _error {
            error_message = "The block could not be moved. Check the runtime and retry.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def start_workflow -> None {
        if pending_action != "" or demo is None or not demo.validation.valid {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "run";
        error_message = "";
        try {
            response = root spawn start_run(
                workflow=demo.workflow, connector_mode=connector_mode
            );
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "Run returned no state. No brief was written; retry from this graph.";
            }
        } except Exception as _error {
            error_message = "The run could not start. No brief was written; check the runtime.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def refresh_run -> None {
        if pending_action != "" or demo is None or demo.run_id == "" {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "refresh";
        error_message = "";
        try {
            response = root spawn get_run(run_id=demo.run_id);
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
                approval_uncertain = False;
            } else {
                error_message = "No persisted run was found. Keep this screen open and retry.";
            }
        } except Exception as _error {
            error_message = "The persisted run could not be refreshed. Retry without starting over.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def decide_approval(approved: bool) -> None {
        if (
            pending_action != ""
            or demo is None
            or str(demo.run_state) != "awaiting_approval"
            or approval_uncertain
        ) {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        decision_request_id = (
            demo.run_id + ":" + str(demo.approval.generation) + ":" + str(epoch)
        );
        pending_action = "decision";
        error_message = "";
        try {
            response = root spawn approve_run(
                run_id=demo.run_id,
                approved=approved,
                effect_digest=demo.approval.effect_digest,
                approval_nonce=demo.approval.nonce,
                decision_request_id=decision_request_id
            );
            if response.reports and len(response.reports) > 0 {
                decision_state = response.reports[0];
                accept_demo(decision_state, epoch);
                outcome = decision_state.approval_outcome;
                if outcome.state == "accepted" {
                    pending_action = "resume";
                    try {
                        resumed = root spawn recover_run(run_id=decision_state.run_id);
                        if resumed.reports and len(resumed.reports) > 0 {
                            accept_demo(resumed.reports[0], epoch);
                        } else {
                            error_message = (
                                "Approval was persisted, but resume returned no state. "
                                "Use Resume persisted run."
                            );
                        }
                    } except Exception as _resume_error {
                        error_message = (
                            "Approval was persisted, but resume could not complete. "
                            "Use Resume persisted run."
                        );
                    }
                } elif outcome.state == "uncertain" {
                    approval_uncertain = True;
                    error_message = outcome.message;
                } elif outcome.state in ["stale", "canceled"] {
                    error_message = outcome.message;
                }
            } else {
                approval_uncertain = True;
                error_message = (
                    "Decision delivery is uncertain. Refresh persisted state; "
                    "do not submit another decision yet."
                );
            }
        } except Exception as _error {
            approval_uncertain = True;
            error_message = (
                "Decision delivery is uncertain. Refresh persisted state; "
                "do not submit another decision yet."
            );
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async def resume_run -> None {
        if (
            pending_action != ""
            or demo is None
            or demo.run_id == ""
            or str(demo.run_state) != "running"
            or demo.approval_outcome.state not in [
                "accepted",
                "already_completed_same_decision"
            ]
        ) {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "resume";
        error_message = "";
        try {
            response = root spawn recover_run(run_id=demo.run_id);
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "The persisted approved run did not resume. Refresh and retry.";
            }
        } except Exception as _error {
            error_message = "The persisted approval remains recorded. Resume or refresh again.";
        }
        if epoch == request_epoch {
            pending_action = "";
        }
    }

    async can with entry {
        await compile_workflow();
    }

    busy = pending_action != "";
    if demo is None {
        return
            <main className="quaze-app loading-shell">
                <div className="loading-mark">QZ</div>
                <p>
                    {busy
                    and "Compiling tomorrow's workflow…"
                    or "The workflow did not load. Retry when the Jac runtime is available."}
                </p>
                {error_message != ""
                and <div className="error-banner" role="alert">{error_message}</div>
                or None}
                {not busy
                and <button
                    type="button"
                    className="button button-primary"
                    onClick={compile_workflow}
                >
                    Retry compile
                </button>
                or None}
            </main>;
    }

    selected_block: BlockSpec | None = None;
    for block in demo.workflow.blocks {
        if block.id == selected_block_id {
            selected_block = block;
        }
    }
    selected_events = (
        events_for_block(demo.events, selected_block_id)
            if selected_block_id != ""
            else []
    );
    run_active = (
        str(demo.run_state) == "running"
        or str(demo.run_state) == "awaiting_approval"
    );
    approval_pair_matches = (
        demo.approval.state == "requested"
        and demo.approval.effect_digest != ""
        and demo.approval.nonce != ""
        and demo.approval.effect_digest == demo.effect_proposal.effect_digest
        and demo.approval.nonce == demo.effect_proposal.approval_nonce
        and demo.approval.generation
            == demo.effect_proposal.approval_generation
        and demo.run_contract.contract_id == demo.effect_proposal.contract_id
    );
    can_approve = (
        approval_pair_matches
        and demo.effect_proposal.state == "ready"
        and demo.effect_proposal.approval_allowed
        and demo.effect_proposal.content_visibility == "full_synthetic_fixture"
        and not demo.effect_proposal.proposed_content_truncated
        and not demo.effect_proposal.diff_truncated
        and not demo.effect_proposal.blockers
    );
    can_reject = (
        demo.approval.state == "requested"
        and demo.approval.nonce != ""
        and demo.approval.effect_digest == demo.effect_proposal.effect_digest
        and demo.approval.nonce == demo.effect_proposal.approval_nonce
        and demo.approval.generation
            == demo.effect_proposal.approval_generation
    );
    can_resume = (
        str(demo.run_state) == "running"
        and demo.approval.state == "approved"
        and demo.approval_outcome.state in [
            "accepted",
            "already_completed_same_decision"
        ]
    );

    return
        <main className="quaze-app">
            <header className="product-header">
                <a href="#workflow" className="brand" aria-label="QuaZe workflow">
                    <span className="brand-mark">QZ</span>
                    <span>
                        <strong>QuaZe</strong>
                        <small>Outcome-to-agent builder</small>
                    </span>
                </a>
                <div className="mode-strip" aria-label="Runtime modes">
                    <ModeLabel
                        label="Compiler"
                        value={demo.compiler_mode}
                        tone={compiler_tone(demo.compiler_mode)}
                    />
                    <ModeLabel label="Connectors" value="fixture only" tone="neutral"/>
                </div>
            </header>
            <section className="prompt-section" aria-labelledby="prompt-title">
                <div className="prompt-heading">
                    <div>
                        <p className="eyebrow">
                            Verified template · first supported workflow
                        </p>
                        <h1 id="prompt-title">Describe the outcome. Keep the proof.</h1>
                    </div>
                    <span className="workflow-version">
                        {demo.workflow.name} · v{str(demo.workflow.version)}
                    </span>
                </div>
                <label for="meeting-prompt">Meeting-prep prompt</label>
                <div className="prompt-control">
                    <textarea
                        id="meeting-prompt"
                        rows={3}
                        value={prompt}
                        disabled={busy or run_active}
                        onChange={lambda (event: ChangeEvent) { prompt = event.target.value; }}
                    ></textarea>
                    <button
                        type="button"
                        className="button button-primary"
                        disabled={busy or run_active or prompt.strip() == ""}
                        onClick={compile_workflow}
                    >
                        {pending_action == "compile"
                        and "Compiling…"
                        or "Compile workflow"}
                    </button>
                </div>
                {demo.compiler_notice != ""
                and <p className="compiler-notice">{demo.compiler_notice}</p>
                or None}
                <p className="connector-safety">
                    Fixture mode uses synthetic calendar and vault records only.
                    Live execution is unavailable in this experimental checkpoint.
                </p>
            </section>
            {error_message != ""
            and <div className="error-banner" role="alert">
                <strong>Action stopped.</strong>
                <span>{error_message}</span>
            </div>
            or None}
            <div id="workflow" className="workflow-layout">
                <BlockLibrary blocks={demo.workflow.blocks}/>
                <ExecutionSpine
                    demo={demo}
                    selected_block_id={selected_block_id}
                    busy={busy or run_active}
                    on_select={lambda (block_id: str) { selected_block_id = block_id; }}
                    on_move={move_block}
                />
                <BlockInspector block={selected_block} events={selected_events}/>
            </div>
            <section className="run-dock" aria-label="Validate and run workflow">
                <ValidationPanel demo={demo}/>
                <div className="run-actions">
                    <button
                        type="button"
                        className="button button-secondary"
                        disabled={busy or run_active}
                        onClick={validate_current}
                    >
                        {pending_action == "validate" and "Validating…" or "Validate"}
                    </button>
                    <button
                        type="button"
                        className="button button-secondary"
                        disabled={busy or demo.run_id == ""}
                        onClick={refresh_run}
                    >
                        {pending_action == "refresh"
                        and "Refreshing…"
                        or "Refresh trace"}
                    </button>
                    {can_resume
                    and <button
                        type="button"
                        className="button button-approval"
                        disabled={busy}
                        onClick={resume_run}
                    >
                        {pending_action == "resume"
                        and "Resuming…"
                        or "Resume persisted run"}
                    </button>
                    or None}
                    <button
                        type="button"
                        className="button button-primary run-button"
                        disabled={busy or run_active or not demo.validation.valid}
                        onClick={start_workflow}
                    >
                        {pending_action == "run"
                        and "Starting run…"
                        or "Run tomorrow brief"}
                    </button>
                </div>
            </section>
            <div className="proof-layout">
                <RunContractPanel demo={demo}/>
                <EffectProposalPanel demo={demo}/>
            </div>
            {str(demo.run_state) == "awaiting_approval"
            and <ApprovalPanel
                demo={demo}
                busy={busy}
                uncertain={approval_uncertain}
                can_approve={can_approve}
                can_reject={can_reject}
                on_decide={decide_approval}
                on_refresh={refresh_run}
            />
            or None}
            <ArtifactPanel demo={demo}/>
            <ReceiptPanel demo={demo}/>
            <footer className="product-footer">
                <span>Calendar is read-only.</span>
                <span>
                    Live execution is unavailable; fixture vault reads stay path-contained.
                </span>
                {demo.run_id != "" and <code>run {demo.run_id}</code> or None}
            </footer>
        </main>;
}
