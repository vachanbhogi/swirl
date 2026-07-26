"""Reusable QuaZe workflow contracts and persistent graph schema.

This module is owned by the integration lead. Parallel agents consume these
types but must not change them without an explicit contract revision. The
contracts model prompt-generated agentic workflows generally; the current
allowlist and runtime prove them through one meeting-prep workflow.
"""

enum RunState {
    IDLE = "idle",
    RUNNING = "running",
    AWAITING_APPROVAL = "awaiting_approval",
    SUCCEEDED = "succeeded",
    FAILED = "failed"
}

enum StepState {
    PENDING = "pending",
    RUNNING = "running",
    SUCCEEDED = "succeeded",
    AWAITING_APPROVAL = "awaiting_approval",
    SKIPPED = "skipped",
    FAILED = "failed"
}

obj ConnectionSpec {
    has source_id: str,
        target_id: str;
}

obj BlockSpec {
    has id: str,
        block_type: str,
        title: str,
        config: dict[str, object] = {},
        inputs: list[str] = [],
        outputs: list[str] = [],
        permissions: list[str] = [];
}

obj ValidationResult {
    has valid: bool = False,
        errors: list[str] = [],
        warnings: list[str] = [];
}

obj WorkflowSpec {
    has id: str,
        name: str,
        version: int,
        blocks: list[BlockSpec],
        connections: list[ConnectionSpec],
        validation: ValidationResult;
}

obj ConnectorResult {
    has success: bool,
        data: dict[str, object] = {},
        evidence_summary: str = "",
        error: str = "";
}

obj RunStepSpec {
    has id: str,
        block_id: str,
        title: str,
        state: StepState = StepState.PENDING,
        attempt: int = 0,
        started_at: str = "",
        completed_at: str = "",
        evidence_summary: str = "",
        error: str = "";
}

obj ApprovalSpec {
    has id: str = "",
        run_id: str = "",
        state: str = "not_requested",
        prompt: str = "",
        requested_at: str = "",
        decided_at: str = "";
}

obj ArtifactSpec {
    has id: str = "",
        run_id: str = "",
        path: str = "",
        content_hash: str = "",
        source_references: list[str] = [],
        state: str = "not_created";
}

obj AgentEventSpec {
    has id: str,
        run_id: str,
        sequence: int,
        event_type: str,
        message: str,
        block_id: str = "",
        created_at: str = "";
}

obj DemoState {
    has workflow: WorkflowSpec,
        validation: ValidationResult,
        run_id: str = "",
        run_state: RunState = RunState.IDLE,
        run_steps: list[RunStepSpec] = [],
        approval: ApprovalSpec = ApprovalSpec(),
        events: list[AgentEventSpec] = [],
        artifact: ArtifactSpec = ArtifactSpec(),
        compiler_mode: str = "deterministic",
        compiler_notice: str = "";
}

node Workflow {
    has workflow_id: str,
        name: str,
        version: int = 1,
        created_at: str = "",
        validation_state: str = "unvalidated",
        validation_errors: list[str] = [],
        validation_warnings: list[str] = [];
}

node Block {
    has block_id: str,
        block_type: str,
        title: str,
        position: int,
        config: dict[str, object] = {},
        inputs: list[str] = [],
        outputs: list[str] = [],
        permissions: list[str] = [];
}

node Run {
    has run_id: str,
        workflow_id: str,
        state: RunState = RunState.IDLE,
        created_at: str = "",
        updated_at: str = "",
        context: dict[str, object] = {};
}

node RunStep {
    has step_id: str,
        block_id: str,
        title: str,
        position: int,
        state: StepState = StepState.PENDING,
        attempt: int = 0,
        started_at: str = "",
        completed_at: str = "",
        evidence_summary: str = "",
        error: str = "";
}

node Approval {
    has approval_id: str,
        run_id: str,
        state: str = "requested",
        prompt: str = "",
        requested_at: str = "",
        decided_at: str = "";
}

node Artifact {
    has artifact_id: str,
        run_id: str,
        path: str,
        content_hash: str = "",
        source_references: list[str] = [],
        state: str = "not_created";
}

node AgentEvent {
    has event_id: str,
        run_id: str,
        sequence: int,
        event_type: str,
        message: str,
        block_id: str = "",
        created_at: str = "";
}

edge ContainsBlock: Workflow --> Block {
    has position: int;
}

edge ExecutionFlow: Block --> Block {
    has position: int;
}

edge HasRun: Workflow --> Run {}

edge HasStep: Run --> RunStep {
    has position: int;
}

edge StepForBlock: RunStep --> Block {}

edge RequiresApproval: Run --> Approval {}

edge HasEvidence: RunStep --> AgentEvent {
    has sequence: int;
}

edge ProducedArtifact: Run --> Artifact {}

edge CitesEvidence: Artifact --> AgentEvent {}
