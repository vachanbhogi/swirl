"""Persistent QuaZe workflow, run, approval, evidence, and artifact graph."""

import datetime;
import uuid;
import from contracts {
    AgentEvent,
    AgentEventSpec,
    Approval,
    ApprovalSpec,
    Artifact,
    ArtifactSpec,
    Block,
    BlockSpec,
    CitesEvidence,
    ConnectionSpec,
    ContainsBlock,
    DemoState,
    ExecutionFlow,
    HasEvidence,
    HasRun,
    HasStep,
    ProducedArtifact,
    RequiresApproval,
    Run,
    RunState,
    RunStep,
    RunStepSpec,
    StepForBlock,
    StepState,
    ValidationResult,
    Workflow,
    WorkflowSpec
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
    existing = find_workflow(spec.id, spec.version);
    if existing is None {
        workflow = root ++> Workflow(
            workflow_id=spec.id,
            name=spec.name,
            version=spec.version,
            created_at=now_iso(),
            validation_state="valid" if validation.valid else "invalid",
            validation_errors=[error for error in validation.errors],
            validation_warnings=[warning for warning in validation.warnings]
        );
    } else {
        # Workflow revisions are immutable once materialized so old runs retain
        # their exact Block and StepForBlock provenance.
        return existing;
    }

    block_by_id: dict[str, Block] = {};
    for (index, block_spec) in enumerate(spec.blocks) {
        block = Block(
            block_id=block_spec.id,
            block_type=block_spec.block_type,
            title=block_spec.title,
            position=index,
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
            source +>:ExecutionFlow(position=index):+> target;
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
                config=block.config,
                inputs=block.inputs,
                outputs=block.outputs,
                permissions=block.permissions
            )
        );
        for target in [block->:ExecutionFlow:->] {
            connections.append(
                ConnectionSpec(source_id=block.block_id, target_id=target.block_id)
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
        validation=validation
    );
}

def create_run_graph(
    workflow: Workflow, spec: WorkflowSpec, connector_mode: str
) -> Run {
    created_at = now_iso();
    run = Run(
        run_id=new_public_id("run"),
        workflow_id=workflow.workflow_id,
        state=RunState.RUNNING,
        created_at=created_at,
        updated_at=created_at,
        context={"connector_mode": connector_mode}
    );
    workflow +>:HasRun:+> run;

    persisted_blocks: dict[str, Block] = {};
    for block in _ordered_blocks(workflow) {
        persisted_blocks[block.block_id] = block;
    }

    for (index, block_spec) in enumerate(spec.blocks) {
        step = RunStep(
            step_id=new_public_id("step"),
            block_id=block_spec.id,
            title=block_spec.title,
            position=index
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
        message=message,
        block_id=step.block_id,
        created_at=now_iso()
    );
    step +>:HasEvidence(sequence=sequence):+> event;
    run.updated_at = event.created_at;
    return event;
}

def request_approval(run: Run, step: RunStep, prompt: str) -> Approval {
    existing = [run->:RequiresApproval:->];
    if existing {
        # A persisted decision is terminal, and an outstanding request must
        # not emit duplicate events when execution is retried.
        return existing[0];
    }
    approval = Approval(
        approval_id=new_public_id("approval"),
        run_id=run.run_id,
        prompt=prompt,
        requested_at=now_iso()
    );
    run +>:RequiresApproval:+> approval;
    step.state = StepState.AWAITING_APPROVAL;
    run.state = RunState.AWAITING_APPROVAL;
    record_step_event(
        run,
        step,
        "approval_requested",
        "Draft ready. Approval is required before Save Brief."
    );
    return approval;
}

def decide_approval(run: Run, approved: bool) -> bool {
    approvals = [run->:RequiresApproval:->];
    if not approvals or approvals[0].state != "requested" {
        return False;
    }
    approval = approvals[0];
    approval.decided_at = now_iso();
    approval_steps = [
        step
        for step in _ordered_steps(run)
        if step.block_id == "approval"
    ];
    if not approval_steps {
        return False;
    }
    step = approval_steps[0];
    step.completed_at = approval.decided_at;
    if approved {
        approval.state = "approved";
        step.state = StepState.SUCCEEDED;
        run.state = RunState.RUNNING;
        record_step_event(
            run, step, "approval_granted", "Approval granted. Resuming the same run."
        );
    } else {
        approval.state = "rejected";
        step.state = StepState.FAILED;
        step.error = "The draft was rejected.";
        run.state = RunState.FAILED;
        record_step_event(
            run, step, "approval_rejected", "Approval rejected. No brief was saved."
        );
    }
    return True;
}

def attach_artifact(
    run: Run, path: str, content_hash: str, source_references: list[str]
) -> Artifact {
    normalized_path = path.replace("\\", "/");
    if not (
        normalized_path == "fixtures/demo-vault/Tomorrow Brief.md"
        or normalized_path.endswith("/fixtures/demo-vault/Tomorrow Brief.md")
    ) {
        raise ValueError(
            "QuaZe may attach only fixtures/demo-vault/Tomorrow Brief.md."
        );
    }
    existing = [run->:ProducedArtifact:->];
    if existing {
        artifact = existing[0];
        artifact.path = normalized_path;
        artifact.content_hash = content_hash;
        artifact.source_references = source_references;
        artifact.state = "created";
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
        path=normalized_path,
        content_hash=content_hash,
        source_references=source_references,
        state="created"
    );
    run +>:ProducedArtifact:+> artifact;
    for event in _run_events(run) {
        artifact +>:CitesEvidence:+> event;
    }
    return artifact;
}

def run_to_demo_state(run: Run) -> DemoState {
    owning_workflows = [run<-:HasRun:<-];
    if owning_workflows {
        workflow_spec = workflow_to_spec(owning_workflows[0]);
    } else {
        workflow_spec = WorkflowSpec(
            id=run.workflow_id,
            name="Unavailable workflow",
            version=1,
            blocks=[],
            connections=[],
            validation=ValidationResult(
                valid=False, errors=["The run is detached from its workflow."]
            )
        );
    }

    step_specs: list[RunStepSpec] = [];
    for step in _ordered_steps(run) {
        step_specs.append(
            RunStepSpec(
                id=step.step_id,
                block_id=step.block_id,
                title=step.title,
                state=step.state,
                attempt=step.attempt,
                started_at=step.started_at,
                completed_at=step.completed_at,
                evidence_summary=step.evidence_summary,
                error=step.error
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
            source_references=artifact_node.source_references,
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
                message=event.message,
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
        compiler_mode="persisted",
        compiler_notice="State loaded from the persisted Jac graph."
    );
}
