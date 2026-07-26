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

def ApprovalPanel(
    demo: DemoState, busy: bool, on_decide: Callable[[bool], None]
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
            </div>
            <div className="approval-actions">
                <button
                    type="button"
                    className="button button-secondary button-danger"
                    disabled={busy}
                    onClick={lambda { on_decide(False); }}
                >
                    Reject &amp; stop
                </button>
                <button
                    type="button"
                    className="button button-approval"
                    disabled={busy}
                    onClick={lambda { on_decide(True); }}
                >
                    Approve &amp; continue
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
        ) {
            return;
        }
        request_epoch += 1;
        epoch = request_epoch;
        pending_action = "approval";
        error_message = "";
        try {
            response = root spawn approve_run(run_id=demo.run_id, approved=approved);
            if response.reports and len(response.reports) > 0 {
                accept_demo(response.reports[0], epoch);
            } else {
                error_message = "The approval decision was not recorded. Retry before closing.";
            }
        } except Exception as _error {
            error_message = "The approval decision could not be recorded. Retry before closing.";
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

    return
        <main className="quaze-app">
            <header className="product-header">
                <a href="#workflow" className="brand" aria-label="QuaZe workflow">
                    <span className="brand-mark">QZ</span>
                    <span>
                        <strong>QuaZe</strong>
                        <small>Tomorrow brief</small>
                    </span>
                </a>
                <div className="mode-strip" aria-label="Runtime modes">
                    <ModeLabel
                        label="Compiler"
                        value={demo.compiler_mode}
                        tone={compiler_tone(demo.compiler_mode)}
                    />
                    <label className="connector-control">
                        <span>Connectors</span>
                        <select
                            aria-label="Connector mode"
                            value={connector_mode}
                            disabled={busy or run_active}
                            onChange={lambda (event: ChangeEvent) { connector_mode = event.target.value; }}
                        >
                            <option value="fixture">Fixture</option>
                            <option value="live">Live demo</option>
                        </select>
                    </label>
                </div>
            </header>
            <section className="prompt-section" aria-labelledby="prompt-title">
                <div className="prompt-heading">
                    <div>
                        <p className="eyebrow">
                            First supported workflow · tomorrow
                        </p>
                        <h1 id="prompt-title">Prepare tomorrow’s meetings</h1>
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
                    {connector_mode == "live"
                    and "Live demo is restricted to the dedicated QuaZe Demo calendar and demo vault."
                    or "Fixture mode uses synthetic calendar and vault records only."}
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
            {str(demo.run_state) == "awaiting_approval"
            and <ApprovalPanel demo={demo} busy={busy} on_decide={decide_approval}/>
            or None}
            <ArtifactPanel demo={demo}/>
            <footer className="product-footer">
                <span>Calendar is read-only.</span>
                <span>
                    Live access is restricted to QuaZe Demo; vault reads stay path-contained.
                </span>
                {demo.run_id != "" and <code>run {demo.run_id}</code> or None}
            </footer>
        </main>;
}
