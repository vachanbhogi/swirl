"""Persistent QuaZe workflow, run, approval, evidence, and artifact graph."""

import datetime;
import json;
import uuid;
import from block_registry { block_catalog, block_definition }
import from contracts {
    AgentEvent,
    AgentEventSpec,
    Approval,
    ApprovalDecisionOutcomeSpec,
    ApprovalSpec,
    Artifact,
    ArtifactSpec,
    Block,
    BlockSpec,
    CitesEvidence,
    CompilerProvenanceSpec,
    ConnectionSpec,
    ContainsBlock,
    DemoState,
    EffectKind,
    EffectProposalSpec,
    ExecutionFlow,
    HasEvidence,
    HasRun,
    HasStep,
    ProducedArtifact,
    RequiresApproval,
    Run,
    RunContractSpec,
    RunReceiptSpec,
    RunState,
    RunStep,
    RunStepSpec,
    StepForBlock,
    StepState,
    ValidationResult,
    Workflow,
    WorkflowSpec
}
import from safety { sanitize_public_message }
import from run_contract {
    LOGICAL_BRIEF_TARGET,
    canonical_snapshot_hash,
    derive_persisted_receipt,
    preflight_for_workflow,
    prepare_write_effect,
    presented_source_references,
    workflow_revision_digest
}

def now_iso -> str {
    return datetime.datetime.now(datetime.timezone.utc).isoformat();
}

def new_public_id(prefix: str) -> str {
    return f"{prefix}-{str(uuid.uuid4())}";
}

def find_workflow(workflow_id: str, version: int | None = None) -> Workflow | None {
    found: Workflow | None = None;
    found_version = -1;
    for workflow in [root-->[?:Workflow]] {
        if (
            workflow.workflow_id == workflow_id
            and (version is None or workflow.version == version)
            and workflow.version > found_version
        ) {
            found = workflow;
            found_version = workflow.version;
        }
    }
    return found;
}

def find_run(run_id: str) -> Run | None {
    for workflow in [root-->[?:Workflow]] {
        for run in [workflow->:HasRun:->] {
            if run.run_id == run_id {
                return run;
            }
        }
    }
    return None;
}


def run_execution_gate_message(run: Run) -> str {
    if run.workflow_version < 2 or run.run_contract.workflow_version < 2 {
        return (
            "Legacy workflow contracts are read-only and unavailable for execution."
        );
    }
    if run.connector_mode != "fixture" or run.run_contract.connector_mode != "fixture" {
        return (
            "Persisted non-fixture runs are read-only and unavailable for execution."
        );
    }
    workflows = [run<-:HasRun:<-];
    if not workflows {
        return "Detached persisted runs are read-only and unavailable for execution.";
    }
    workflow = workflows[0];
    if (
        run.run_contract.state != "ready"
        or not run.run_contract.contract_id
        or not workflow.revision_digest
        or workflow.version != run.workflow_version
        or run.run_contract.workflow_version != run.workflow_version
        or run.run_contract.workflow_revision_digest != workflow.revision_digest
    ) {
        return (
            "The persisted run does not match the current published workflow "
            "contract and is read-only."
        );
    }
    return "";
}

def _ordered_blocks(workflow: Workflow) -> list[Block] {
    blocks = [workflow->:ContainsBlock:->];
    blocks.sort(key=lambda (block: Block) { block.position; });
    return blocks;
}

def _ordered_steps(run: Run) -> list[RunStep] {
    steps = [run->:HasStep:->];
    steps.sort(key=lambda (step: RunStep) { step.position; });
    return steps;
}

def _run_events(run: Run) -> list[AgentEvent] {
    events: list[AgentEvent] = [];
    for step in _ordered_steps(run) {
        for event in [step->:HasEvidence:->] {
            events.append(event);
        }
    }
    events.sort(key=lambda (event: AgentEvent) { event.sequence; });
    return events;
}

def materialize_workflow(spec: WorkflowSpec, validation: ValidationResult) -> Workflow {
    revision_digest = workflow_revision_digest(spec);
    existing = find_workflow(spec.id, spec.version);
    if existing is None {
        workflow = root ++> Workflow(
            workflow_id=spec.id,
            name=spec.name,
            version=spec.version,
            created_at=now_iso(),
            revision_digest=revision_digest,
            compiler_provenance=spec.compiler_provenance,
            validation_state="valid" if validation.valid else "invalid",
            validation_errors=[error for error in validation.errors],
            validation_warnings=[warning for warning in validation.warnings]
        );
    } else {
        # Workflow revisions are immutable once materialized so old runs retain
        # their exact Block and StepForBlock provenance.
        if existing.revision_digest != revision_digest {
            raise ValueError(
                (
                    f"Workflow {spec.id} version {spec.version} already exists "
                    "with different content. Publish a new workflow version."
                )
            );
        }
        return existing;
    }

    block_by_id: dict[str, Block] = {};
    for (index, block_spec) in enumerate(spec.blocks) {
        block = Block(
            block_id=block_spec.id,
            block_type=block_spec.block_type,
            title=block_spec.title,
            position=index,
            block_version=block_spec.block_version,
            config_version=block_spec.config_version,
            config=block_spec.config,
            inputs=block_spec.inputs,
            outputs=block_spec.outputs,
            permissions=block_spec.permissions
        );
        workflow +>:ContainsBlock(position=index):+> block;
        block_by_id[block.block_id] = block;
    }

    for (index, connection) in enumerate(spec.connections) {
        source = block_by_id.get(connection.source_id);
        target = block_by_id.get(connection.target_id);
        if source is not None and target is not None {
            source +>:ExecutionFlow(
                position=index,
                source_port=connection.source_port,
                target_port=connection.target_port
            ):+> target;
        }
    }
    return workflow;
}

def workflow_to_spec(workflow: Workflow) -> WorkflowSpec {
    blocks: list[BlockSpec] = [];
    connections: list[ConnectionSpec] = [];
    for block in _ordered_blocks(workflow) {
        blocks.append(
            BlockSpec(
                id=block.block_id,
                block_type=block.block_type,
                title=block.title,
                block_version=block.block_version,
                config_version=block.config_version,
                config=block.config,
                inputs=block.inputs,
                outputs=block.outputs,
                permissions=block.permissions
            )
        );
        targets = [block->:ExecutionFlow:->];
        flow_edges = [edge block->:ExecutionFlow:->];
        for (target_index, target) in enumerate(targets) {
            execution_edge: ExecutionFlow = flow_edges[target_index];
            connections.append(
                ConnectionSpec(
                    source_id=block.block_id,
                    target_id=target.block_id,
                    source_port=execution_edge.source_port,
                    target_port=execution_edge.target_port
                )
            );
        }
    }
    validation = ValidationResult(
        valid=workflow.validation_state == "valid",
        errors=[error for error in workflow.validation_errors],
        warnings=[warning for warning in workflow.validation_warnings]
    );
    return WorkflowSpec(
        id=workflow.workflow_id,
        name=workflow.name,
        version=workflow.version,
        blocks=blocks,
        connections=connections,
        validation=validation,
        compiler_provenance=workflow.compiler_provenance
    );
}

def create_run_graph(
    workflow: Workflow, spec: WorkflowSpec, connector_mode: str
) -> Run {
    if workflow.version < 2 or spec.version < 2 {
        raise ValueError(
            "Legacy workflow version 1 is read-only and cannot start a new run."
        );
    }
    if workflow.version != spec.version {
        raise ValueError("The materialized workflow version does not match the run.");
    }
    created_at = now_iso();
    run_id = new_public_id("run");
    run_contract = preflight_for_workflow(spec, connector_mode, run_id);
    run = Run(
        run_id=run_id,
        workflow_id=workflow.workflow_id,
        state=RunState.RUNNING,
        created_at=created_at,
        updated_at=created_at,
        workflow_version=workflow.version,
        idempotency_key=run_contract.contract_id,
        connector_mode=connector_mode,
        compiler_provenance=spec.compiler_provenance,
        run_contract=run_contract,
        context={"connector_mode": connector_mode}
    );
    workflow +>:HasRun:+> run;

    persisted_blocks: dict[str, Block] = {};
    for block in _ordered_blocks(workflow) {
        persisted_blocks[block.block_id] = block;
    }

    for (index, block_spec) in enumerate(spec.blocks) {
        definition = block_definition(block_spec.block_type);
        if definition is None {
            raise ValueError(
                f"Cannot create a run for unsupported block {block_spec.block_type}."
            );
        }
        step = RunStep(
            step_id=new_public_id("step"),
            block_id=block_spec.id,
            title=block_spec.title,
            position=index,
            block_type=block_spec.block_type,
            block_version=block_spec.block_version,
            config_version=block_spec.config_version,
            idempotency_key=(
                run_contract.contract_id + ":" + block_spec.id + ":"
                + str(block_spec.block_version) + ":"
                + str(block_spec.config_version)
            ),
            planned_effect=definition.effect_policy.kind
        );
        run +>:HasStep(position=index):+> step;
        block = persisted_blocks.get(block_spec.id);
        if block is not None {
            step +>:StepForBlock:+> block;
        }
    }
    return run;
}

def record_step_event(
    run: Run, step: RunStep, event_type: str, message: str
) -> AgentEvent {
    sequence = len(_run_events(run)) + 1;
    event = AgentEvent(
        event_id=new_public_id("event"),
        run_id=run.run_id,
        sequence=sequence,
        event_type=event_type,
        message=sanitize_public_message(message),
        block_id=step.block_id,
        created_at=now_iso()
    );
    step +>:HasEvidence(sequence=sequence):+> event;
    run.updated_at = event.created_at;
    return event;
}

def persist_step_output(
    run: Run,
    step: RunStep,
    outputs: dict[str, object],
    evidence_snapshot_hashes: list[str],
    performed_effect: EffectKind
) {
    step.outputs = outputs;
    step.evidence_snapshot_hashes = evidence_snapshot_hashes;
    step.performed_effect = performed_effect;
    for key in outputs {
        run.context[key] = outputs[key];
    }
    run.updated_at = now_iso();
}


def rebuild_run_context(run: Run) {
    connector_mode = run.connector_mode;
    rebuilt: dict[str, object] = {"connector_mode": connector_mode};
    for step in _ordered_steps(run) {
        if step.state in [StepState.SUCCEEDED, StepState.SKIPPED] {
            for key in step.outputs {
                rebuilt[key] = step.outputs[key];
            }
        }
    }
    run.context = rebuilt;
}


def _approval_step(run: Run) -> RunStep | None {
    for step in _ordered_steps(run) {
        if step.block_type == "approval" {
            return step;
        }
    }
    return None;
}


def _refresh_approval(
    run: Run, step: RunStep, prompt: str, stale_reason: str = ""
) -> Approval {
    run.approval_generation += 1;
    nonce = new_public_id("approval-nonce");
    proposal = prepare_write_effect(
        run,
        run.approval_generation,
        nonce,
        persist_snapshot=True
    );
    run.effect_proposal = proposal;
    existing = [run->:RequiresApproval:->];
    if existing {
        approval = existing[0];
        approval.state = "requested";
        approval.prompt = prompt;
        approval.effect_digest = proposal.effect_digest;
        approval.nonce = nonce;
        approval.generation = run.approval_generation;
        approval.decision_digest = "";
        approval.decision_nonce = "";
        approval.decision_request_id = "";
        approval.stale_reason = stale_reason;
        approval.requested_at = now_iso();
        approval.decided_at = "";
    } else {
        approval = Approval(
            approval_id=new_public_id("approval"),
            run_id=run.run_id,
            prompt=prompt,
            effect_digest=proposal.effect_digest,
            nonce=nonce,
            generation=run.approval_generation,
            stale_reason=stale_reason,
            requested_at=now_iso()
        );
        run +>:RequiresApproval:+> approval;
    }
    step.state = StepState.AWAITING_APPROVAL;
    step.retry_state = "review_required";
    run.state = RunState.AWAITING_APPROVAL;
    record_step_event(
        run,
        step,
        "approval_requested",
        (
            "The bounded write contract changed; review is required again."
                if stale_reason
                else "An exact write contract is ready for review."
        )
    );
    return approval;
}


def _block_approval_review(
    run: Run, step: RunStep, prompt: str, stale_reason: str
) -> Approval {
    run.approval_generation += 1;
    nonce = new_public_id("approval-nonce");
    existing = [run->:RequiresApproval:->];
    if existing {
        approval = existing[0];
        approval.state = "requested";
        approval.prompt = prompt;
        approval.effect_digest = "";
        approval.nonce = nonce;
        approval.generation = run.approval_generation;
        approval.decision_digest = "";
        approval.decision_nonce = "";
        approval.decision_request_id = "";
        approval.stale_reason = stale_reason;
        approval.requested_at = now_iso();
        approval.decided_at = "";
    } else {
        approval = Approval(
            approval_id=new_public_id("approval"),
            run_id=run.run_id,
            prompt=prompt,
            nonce=nonce,
            generation=run.approval_generation,
            stale_reason=stale_reason,
            requested_at=now_iso()
        );
        run +>:RequiresApproval:+> approval;
    }
    run.effect_proposal = EffectProposalSpec(
        state="blocked",
        content_visibility="redacted",
        approval_generation=run.approval_generation,
        approval_nonce=nonce,
        connector_mode=run.connector_mode,
        target=LOGICAL_BRIEF_TARGET,
        remaining_effects=["write:save-brief", "open:open-result"],
        approval_allowed=False,
        blockers=[stale_reason]
    );
    run.contract_snapshot = "";
    run.contract_snapshot_hash = "";
    run.run_contract.contract_snapshot_hash = "";
    step.state = StepState.AWAITING_APPROVAL;
    step.retry_state = "review_blocked";
    run.state = RunState.AWAITING_APPROVAL;
    record_step_event(
        run,
        step,
        "approval_blocked",
        "The exact write contract is unavailable; review remains blocked."
    );
    return approval;
}


def _request_review(
    run: Run, step: RunStep, prompt: str, stale_reason: str = ""
) -> Approval {
    try {
        return _refresh_approval(run, step, prompt, stale_reason);
    } except ValueError as _error {
        return _block_approval_review(
            run,
            step,
            prompt,
            (
                stale_reason
                    if stale_reason
                    else "The exact write target or payload is unavailable."
            )
        );
    }
}


def request_approval(run: Run, step: RunStep, prompt: str) -> Approval {
    existing = [run->:RequiresApproval:->];
    if existing and existing[0].state == "requested" {
        return existing[0];
    }
    if existing and existing[0].state in ["approved", "rejected"] {
        return existing[0];
    }
    return _request_review(run, step, prompt);
}


def refresh_stale_approval(run: Run, stale_reason: str) -> bool {
    step = _approval_step(run);
    approvals = [run->:RequiresApproval:->];
    if step is None or not approvals {
        return False;
    }
    _request_review(run, step, approvals[0].prompt, stale_reason);
    return True;
}


def _transient_approval_outcome(
    run: Run,
    state: str,
    decision_request_id: str,
    approved: bool,
    message: str,
    approval: Approval | None = None
) -> ApprovalDecisionOutcomeSpec {
    outcome = ApprovalDecisionOutcomeSpec(
        state=state,
        run_id=run.run_id,
        decision_request_id=decision_request_id,
        approved=approved,
        approval_generation=approval.generation if approval is not None else 0,
        effect_digest=approval.effect_digest if approval is not None else "",
        approval_nonce=approval.nonce if approval is not None else "",
        message=sanitize_public_message(message)
    );
    return outcome;
}


def _approval_outcome_record(
    outcome: ApprovalDecisionOutcomeSpec,
    submitted_effect_digest: str,
    submitted_approval_nonce: str
) -> str {
    return json.dumps(
        {
            "state": outcome.state,
            "run_id": outcome.run_id,
            "decision_request_id": outcome.decision_request_id,
            "approved": outcome.approved,
            "approval_generation": outcome.approval_generation,
            "effect_digest": outcome.effect_digest,
            "approval_nonce": outcome.approval_nonce,
            "message": outcome.message,
            "submitted_effect_digest": submitted_effect_digest,
            "submitted_approval_nonce": submitted_approval_nonce
        },
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True
    );
}


def _record_string(data: dict[str, object], key: str) -> str {
    value = data.get(key);
    return value if isinstance(value, str) else "";
}


def _record_int(data: dict[str, object], key: str) -> int {
    value = data.get(key);
    return value if isinstance(value, int) else 0;
}


def _recorded_approval_outcome(
    record: str,
    decision_request_id: str,
    approved: bool,
    submitted_effect_digest: str,
    submitted_approval_nonce: str
) -> ApprovalDecisionOutcomeSpec | None {
    try {
        raw = json.loads(record);
    } except Exception as _error {
        return None;
    }
    if not isinstance(raw, dict) {
        return None;
    }
    data = raw as dict[str, object];
    prior_approved = data.get("approved");
    prior_digest = data.get("submitted_effect_digest");
    prior_nonce = data.get("submitted_approval_nonce");
    if (
        not isinstance(prior_approved, bool)
        or not isinstance(prior_digest, str)
        or not isinstance(prior_nonce, str)
        or prior_approved != approved
        or prior_digest != submitted_effect_digest
        or prior_nonce != submitted_approval_nonce
    ) {
        return None;
    }
    return ApprovalDecisionOutcomeSpec(
        state=_record_string(data, "state") or "uncertain",
        run_id=_record_string(data, "run_id"),
        decision_request_id=decision_request_id,
        approved=prior_approved,
        approval_generation=_record_int(data, "approval_generation"),
        effect_digest=_record_string(data, "effect_digest"),
        approval_nonce=_record_string(data, "approval_nonce"),
        message=_record_string(data, "message")
    );
}


def _persist_approval_outcome(
    run: Run,
    outcome: ApprovalDecisionOutcomeSpec,
    submitted_effect_digest: str,
    submitted_approval_nonce: str
) -> ApprovalDecisionOutcomeSpec {
    if outcome.decision_request_id {
        if outcome.decision_request_id not in run.approval_decision_requests {
            run.approval_decision_requests[outcome.decision_request_id] = (
                _approval_outcome_record(
                    outcome,
                    submitted_effect_digest,
                    submitted_approval_nonce
                )
            );
            run.last_approval_outcome = outcome;
        }
    }
    return outcome;
}


def _approval_outcome(
    run: Run,
    state: str,
    decision_request_id: str,
    approved: bool,
    submitted_pair: list[str],
    message: str,
    approval: Approval | None = None
) -> ApprovalDecisionOutcomeSpec {
    return _persist_approval_outcome(
        run,
        _transient_approval_outcome(
            run,
            state,
            decision_request_id,
            approved,
            message,
            approval
        ),
        submitted_pair[0] if submitted_pair else "",
        submitted_pair[1] if len(submitted_pair) > 1 else ""
    );
}


def decide_approval(
    run: Run,
    approved: bool,
    effect_digest: str,
    approval_nonce: str,
    decision_request_id: str
) -> ApprovalDecisionOutcomeSpec {
    approvals = [run->:RequiresApproval:->];
    approval: Approval | None = approvals[0] if approvals else None;
    if not decision_request_id.strip() {
        return _transient_approval_outcome(
            run,
            "uncertain",
            decision_request_id,
            approved,
            "A non-empty decision request ID is required for reconciliation.",
            approval
        );
    }
    prior_request = run.approval_decision_requests.get(decision_request_id);
    if isinstance(prior_request, str) {
        recorded = _recorded_approval_outcome(
            prior_request,
            decision_request_id,
            approved,
            effect_digest,
            approval_nonce
        );
        if recorded is not None {
            return recorded;
        }
        return _transient_approval_outcome(
            run,
            "uncertain",
            decision_request_id,
            approved,
            (
                "The decision request ID was already used with different "
                "decision inputs."
            ),
            approval
        );
    }
    execution_blocker = run_execution_gate_message(run);
    if execution_blocker {
        return _transient_approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            execution_blocker,
            approval
        );
    }
    if run.state == RunState.CANCELED or (
        approval is not None and approval.state == "canceled"
    ) {
        return _approval_outcome(
            run,
            "canceled",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The run and its requested approval were canceled.",
            approval
        );
    }
    if approval is not None and approval.state in ["approved", "rejected"] {
        same_decision = (
            approved and approval.state == "approved"
        ) or (
            not approved and approval.state == "rejected"
        );
        return _approval_outcome(
            run,
            (
                "already_completed_same_decision"
                    if same_decision
                    else "stale"
            ),
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            (
                "The same logical decision was already persisted."
                    if same_decision
                    else "The approval already has a different terminal decision."
            ),
            approval
        );
    }
    if approval is None {
        return _approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The run is not awaiting this approval.",
            approval
        );
    }
    active_approval: Approval = approval;
    if (
        active_approval.state != "requested"
        or run.state != RunState.AWAITING_APPROVAL
    ) {
        return _approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The run is not awaiting this approval.",
            active_approval
        );
    }
    step = _approval_step(run);
    if step is None {
        return _approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The persisted approval step is not awaiting a decision.",
            active_approval
        );
    }
    approval_step: RunStep = step;
    if approval_step.state != StepState.AWAITING_APPROVAL {
        return _approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The persisted approval step is not awaiting a decision.",
            active_approval
        );
    }
    if (
        effect_digest != active_approval.effect_digest
        or approval_nonce != active_approval.nonce
    ) {
        message = "The submitted review pair is stale or does not match.";
        if approved {
            _request_review(
                run, approval_step, active_approval.prompt, message
            );
            active_approval = [run->:RequiresApproval:->][0];
        }
        return _approval_outcome(
            run,
            "stale",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            message,
            active_approval
        );
    }
    if approved {
        try {
            current = prepare_write_effect(
                run, active_approval.generation, active_approval.nonce
            );
        } except ValueError as _error {
            _block_approval_review(
                run,
                approval_step,
                active_approval.prompt,
                "The exact write target or payload is unavailable."
            );
            return _approval_outcome(
                run,
                "stale",
                decision_request_id,
                approved,
                [effect_digest, approval_nonce],
                "The exact write target or payload is unavailable.",
                [run->:RequiresApproval:->][0]
            );
        }
        stale_reason = "";
        if not current.approval_allowed {
            stale_reason = (
                current.blockers[0]
                    if current.blockers
                    else "The server-owned exact-review rule blocked approval."
            );
        } elif current.effect_digest != active_approval.effect_digest {
            stale_reason = "The prepared write changed after it was displayed.";
        } elif run.contract_snapshot_hash != active_approval.effect_digest {
            stale_reason = "The persisted contract snapshot no longer matches.";
        } elif canonical_snapshot_hash(run.contract_snapshot) != (
            active_approval.effect_digest
        ) {
            stale_reason = "The persisted canonical contract bytes changed.";
        }
        if stale_reason {
            _request_review(
                run, approval_step, active_approval.prompt, stale_reason
            );
            return _approval_outcome(
                run,
                "stale",
                decision_request_id,
                approved,
                [effect_digest, approval_nonce],
                stale_reason,
                [run->:RequiresApproval:->][0]
            );
        }
        run.effect_proposal = current;
        active_approval.decided_at = now_iso();
        active_approval.state = "approved";
        active_approval.decision_digest = effect_digest;
        active_approval.decision_nonce = approval_nonce;
        active_approval.decision_request_id = decision_request_id;
        active_approval.stale_reason = "";
        draft_step = [
            candidate
            for candidate in _ordered_steps(run)
            if candidate.block_type == "draft_brief"
        ][0];
        approved_brief_value = draft_step.outputs.get("brief_markdown");
        approved_brief = (
            approved_brief_value
                if isinstance(approved_brief_value, str)
                else ""
        );
        persist_step_output(
            run,
            approval_step,
            {"approved_brief": approved_brief},
            [entry for entry in current.evidence_snapshot_hashes],
            approval_step.planned_effect
        );
        approval_step.state = StepState.SUCCEEDED;
        approval_step.retry_state = "complete";
        approval_step.completed_at = active_approval.decided_at;
        approval_step.effect_digest = effect_digest;
        run.state = RunState.RUNNING;
        record_step_event(
            run,
            approval_step,
            "approval_granted",
            "The server-issued effect contract was approved and persisted."
        );
        return _approval_outcome(
            run,
            "accepted",
            decision_request_id,
            approved,
            [effect_digest, approval_nonce],
            "The exact approval decision was persisted. Resume is now required.",
            active_approval
        );
    }

    active_approval.decided_at = now_iso();
    active_approval.state = "rejected";
    active_approval.decision_digest = effect_digest;
    active_approval.decision_nonce = approval_nonce;
    active_approval.decision_request_id = decision_request_id;
    approval_step.state = StepState.FAILED;
    approval_step.retry_state = "rejected";
    approval_step.completed_at = active_approval.decided_at;
    approval_step.error = "The draft was rejected.";
    run.state = RunState.FAILED;
    record_step_event(
        run,
        approval_step,
        "approval_rejected",
        "Approval rejected. No brief was saved."
    );
    derive_persisted_receipt(run);
    return _approval_outcome(
        run,
        "rejected",
        decision_request_id,
        approved,
        [effect_digest, approval_nonce],
        "The exact review was rejected. No write was performed.",
        active_approval
    );
}

def approved_effect_is_current(run: Run) -> bool {
    if run_execution_gate_message(run) {
        return False;
    }
    approvals = [run->:RequiresApproval:->];
    if not approvals or approvals[0].state != "approved" {
        return False;
    }
    approval = approvals[0];
    try {
        current = prepare_write_effect(
            run, approval.generation, approval.nonce
        );
    } except ValueError as _error {
        step = _approval_step(run);
        if step is not None {
            _block_approval_review(
                run,
                step,
                approval.prompt,
                "The exact write target or payload is unavailable."
            );
        }
        return False;
    }
    if (
        approval.decision_digest == approval.effect_digest
        and approval.decision_nonce == approval.nonce
        and current.approval_allowed
        and current.effect_digest == approval.effect_digest
        and run.contract_snapshot_hash == approval.effect_digest
        and canonical_snapshot_hash(run.contract_snapshot)
            == approval.effect_digest
    ) {
        run.effect_proposal = current;
        return True;
    }
    refresh_stale_approval(
        run, "The target, payload, workflow, connector, or evidence changed."
    );
    return False;
}


def cancel_persisted_run(run: Run) -> bool {
    if run.state in [RunState.SUCCEEDED, RunState.FAILED, RunState.CANCELED] {
        return False;
    }
    run.cancel_requested = True;
    run.state = RunState.CANCELED;
    run.updated_at = now_iso();
    approvals = [run->:RequiresApproval:->];
    if approvals and approvals[0].state == "requested" {
        approval = approvals[0];
        approval.state = "canceled";
        approval.stale_reason = "The run was canceled before a decision.";
        approval.decided_at = run.updated_at;
    }
    for step in _ordered_steps(run) {
        if step.state in [
            StepState.PENDING,
            StepState.RUNNING,
            StepState.AWAITING_APPROVAL
        ] {
            step.state = StepState.CANCELED;
            step.completed_at = run.updated_at;
            step.retry_state = "canceled";
        }
    }
    derive_persisted_receipt(run);
    return True;
}


def recover_persisted_run(run: Run) -> bool {
    if run_execution_gate_message(run) {
        return False;
    }
    if run.state not in [RunState.RUNNING, RunState.AWAITING_APPROVAL] {
        return False;
    }
    run.recovered_at = now_iso();
    run.recovery_count += 1;
    for step in _ordered_steps(run) {
        if step.state == StepState.RUNNING {
            artifacts = [run->:ProducedArtifact:->];
            approvals = [run->:RequiresApproval:->];
            if (
                step.block_type == "save_brief"
                and artifacts
                and approvals
                and approvals[0].state == "approved"
                and artifacts[0].effect_digest == approvals[0].decision_digest
                and artifacts[0].content_hash
                    == run.effect_proposal.proposed_payload_hash
                and artifacts[0].write_state in [
                    "create",
                    "update",
                    "no_change"
                ]
            ) {
                artifact = artifacts[0];
                step.outputs = {
                    "artifact_path": artifact.path,
                    "artifact_hash": artifact.content_hash,
                    "write_state": artifact.write_state
                };
                step.performed_effect = (
                    EffectKind.NONE
                        if artifact.write_state == "no_change"
                        else EffectKind.WRITE
                );
                step.effect_digest = artifact.effect_digest;
                step.state = StepState.SUCCEEDED;
                step.retry_state = "reconciled";
                step.completed_at = run.recovered_at;
                step.evidence_summary = (
                    "Recovered the persisted artifact outcome without "
                    "repeating the filesystem effect."
                );
                record_step_event(
                    run,
                    step,
                    "effect_reconciled",
                    "The persisted artifact outcome was reconciled after restart."
                );
                continue;
            }
            step.state = StepState.PENDING;
            step.retry_state = "recovered";
        }
    }
    rebuild_run_context(run);
    return True;
}


def prepare_failed_run_retry(run: Run) -> bool {
    if run_execution_gate_message(run) {
        return False;
    }
    if run.state != RunState.FAILED {
        return False;
    }
    for step in _ordered_steps(run) {
        if step.state != StepState.FAILED {
            continue;
        }
        definition = block_definition(step.block_type);
        if (
            definition is None
            or step.attempt >= definition.retry_policy.max_attempts
            or not definition.retry_policy.idempotent
        ) {
            return False;
        }
        step.state = StepState.PENDING;
        step.error = "";
        step.completed_at = "";
        step.retry_state = "requested";
        run.retry_count += 1;
        run.state = RunState.RUNNING;
        run.receipt = RunReceiptSpec();
        rebuild_run_context(run);
        return True;
    }
    return False;
}


def attach_artifact(
    run: Run,
    path: str,
    content_hash: str,
    source_references: list[str],
    effect_digest: str = "",
    write_state: str = ""
) -> Artifact {
    normalized_path = path.replace("\\", "/");
    if normalized_path != "fixtures/demo-vault/Tomorrow Brief.md" {
        raise ValueError(
            "QuaZe may attach only fixtures/demo-vault/Tomorrow Brief.md."
        );
    }
    artifact_state = (
        "verified_existing"
            if write_state == "no_change"
            else "updated" if write_state == "update" else "created"
    );
    existing = [run->:ProducedArtifact:->];
    if existing {
        artifact = existing[0];
        artifact.path = "fixtures/demo-vault/Tomorrow Brief.md";
        artifact.content_hash = content_hash;
        artifact.effect_digest = effect_digest;
        artifact.write_state = write_state;
        artifact.source_references = source_references;
        artifact.state = artifact_state;
        cited_events = [artifact->:CitesEvidence:->];
        for event in _run_events(run) {
            if event not in cited_events {
                artifact +>:CitesEvidence:+> event;
            }
        }
        return artifact;
    }
    artifact = Artifact(
        artifact_id=new_public_id("artifact"),
        run_id=run.run_id,
        path="fixtures/demo-vault/Tomorrow Brief.md",
        content_hash=content_hash,
        effect_digest=effect_digest,
        write_state=write_state,
        source_references=source_references,
        state=artifact_state
    );
    run +>:ProducedArtifact:+> artifact;
    for event in _run_events(run) {
        artifact +>:CitesEvidence:+> event;
    }
    return artifact;
}


def _projected_run_contract(run: Run) -> RunContractSpec {
    persisted = run.run_contract;
    projected = RunContractSpec(
        state=persisted.state,
        enforcement_level=persisted.enforcement_level,
        contract_id=persisted.contract_id,
        contract_snapshot_hash=persisted.contract_snapshot_hash,
        workflow_version=persisted.workflow_version,
        workflow_revision_digest=persisted.workflow_revision_digest,
        connector_mode=persisted.connector_mode,
        read_count=persisted.read_count,
        transform_count=persisted.transform_count,
        approval_count=persisted.approval_count,
        write_count=persisted.write_count,
        open_count=persisted.open_count,
        send_count=persisted.send_count,
        delete_count=persisted.delete_count,
        purchase_count=persisted.purchase_count,
        maximum_affected_items=persisted.maximum_affected_items,
        required_permissions=[
            permission for permission in persisted.required_permissions
        ],
        resource_scopes=[scope for scope in persisted.resource_scopes],
        outbound_data=[entry for entry in persisted.outbound_data],
        required_approvals=[
            approval for approval in persisted.required_approvals
        ],
        retry_policy=[policy for policy in persisted.retry_policy],
        duplicate_protection=persisted.duplicate_protection,
        irreversible_effects=[
            effect for effect in persisted.irreversible_effects
        ],
        blockers=[blocker for blocker in persisted.blockers]
    );
    execution_blocker = run_execution_gate_message(run);
    if execution_blocker {
        projected.state = "unavailable";
        if execution_blocker not in projected.blockers {
            projected.blockers.append(execution_blocker);
        }
    }
    return projected;
}


def run_to_demo_state(run: Run) -> DemoState {
    owning_workflows = [run<-:HasRun:<-];
    if owning_workflows {
        workflow_spec = workflow_to_spec(owning_workflows[0]);
        workflow_spec.compiler_provenance = run.compiler_provenance;
    } else {
        workflow_spec = WorkflowSpec(
            id=run.workflow_id,
            name="Unavailable workflow",
            version=run.workflow_version,
            blocks=[],
            connections=[],
            validation=ValidationResult(
                valid=False, errors=["The run is detached from its workflow."]
            ),
            compiler_provenance=run.compiler_provenance
        );
    }

    step_specs: list[RunStepSpec] = [];
    for step in _ordered_steps(run) {
        step_specs.append(
            RunStepSpec(
                id=step.step_id,
                block_id=step.block_id,
                title=step.title,
                block_type=step.block_type,
                block_version=step.block_version,
                config_version=step.config_version,
                state=step.state,
                attempt=step.attempt,
                retry_state=step.retry_state,
                started_at=step.started_at,
                completed_at=step.completed_at,
                evidence_summary=sanitize_public_message(
                    step.evidence_summary, ""
                ),
                evidence_snapshot_hashes=step.evidence_snapshot_hashes,
                planned_effect=step.planned_effect,
                performed_effect=step.performed_effect,
                effect_digest=step.effect_digest,
                error=sanitize_public_message(step.error, "")
            )
        );
    }

    approvals = [run->:RequiresApproval:->];
    if approvals {
        approval_node = approvals[0];
        approval_spec = ApprovalSpec(
            id=approval_node.approval_id,
            run_id=approval_node.run_id,
            state=approval_node.state,
            prompt=approval_node.prompt,
            effect_digest=approval_node.effect_digest,
            nonce=approval_node.nonce,
            generation=approval_node.generation,
            decision_digest=approval_node.decision_digest,
            decision_nonce=approval_node.decision_nonce,
            decision_request_id=approval_node.decision_request_id,
            stale_reason=approval_node.stale_reason,
            requested_at=approval_node.requested_at,
            decided_at=approval_node.decided_at
        );
    } else {
        approval_spec = ApprovalSpec(run_id=run.run_id);
    }

    artifacts = [run->:ProducedArtifact:->];
    if artifacts {
        artifact_node = artifacts[0];
        artifact_spec = ArtifactSpec(
            id=artifact_node.artifact_id,
            run_id=artifact_node.run_id,
            path=artifact_node.path,
            content_hash=artifact_node.content_hash,
            effect_digest=artifact_node.effect_digest,
            write_state=artifact_node.write_state,
            source_references=presented_source_references(
                artifact_node.source_references, run.connector_mode
            ),
            state=artifact_node.state
        );
    } else {
        artifact_spec = ArtifactSpec(run_id=run.run_id);
    }

    event_specs: list[AgentEventSpec] = [];
    for event in _run_events(run) {
        event_specs.append(
            AgentEventSpec(
                id=event.event_id,
                run_id=event.run_id,
                sequence=event.sequence,
                event_type=event.event_type,
                message=sanitize_public_message(event.message),
                block_id=event.block_id,
                created_at=event.created_at
            )
        );
    }

    return DemoState(
        workflow=workflow_spec,
        validation=workflow_spec.validation,
        run_id=run.run_id,
        run_state=run.state,
        run_steps=step_specs,
        approval=approval_spec,
        events=event_specs,
        artifact=artifact_spec,
        block_catalog=block_catalog(),
        run_contract=_projected_run_contract(run),
        effect_proposal=run.effect_proposal,
        receipt=run.receipt,
        compiler_provenance=run.compiler_provenance,
        approval_outcome=run.last_approval_outcome,
        compiler_mode=run.compiler_provenance.mode,
        compiler_notice=(
            "Compiler origin preserved from persisted workflow state."
        )
    );
}
