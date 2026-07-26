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
    FAILED = "failed",
    CANCELED = "canceled"
}

enum StepState {
    PENDING = "pending",
    RUNNING = "running",
    SUCCEEDED = "succeeded",
    AWAITING_APPROVAL = "awaiting_approval",
    SKIPPED = "skipped",
    FAILED = "failed",
    CANCELED = "canceled"
}

enum EffectKind {
    NONE = "none",
    READ = "read",
    TRANSFORM = "transform",
    APPROVAL = "approval",
    WRITE = "write",
    OPEN = "open",
    SEND = "send",
    DELETE = "delete",
    PURCHASE = "purchase"
}

obj ConnectionSpec {
    has source_id: str,
        target_id: str,
        source_port: str = "",
        target_port: str = "";
}

obj PortSpec {
    has name: str,
        label: str,
        data_type: str,
        required: bool = True;
}

obj ConfigFieldSpec {
    has key: str,
        label: str,
        value_type: str,
        required: bool = False,
        default_value: str = "",
        allowed_values: list[str] = [],
        help_text: str = "",
        secret: bool = False;
}

obj ConnectorRequirementSpec {
    has connector_id: str,
        permission: str,
        implementation_version: int = 1,
        required: bool = True;
}

obj RetryPolicySpec {
    has max_attempts: int = 1,
        idempotent: bool = False,
        backoff_ms: int = 0;
}

obj EffectPolicySpec {
    has kind: EffectKind = EffectKind.NONE,
        preview_allowed: bool = False,
        requires_approval: bool = False,
        target_scope: str = "",
        maximum_affected_items: int = 0;
}

obj BlockDefinitionSpec {
    has block_type: str,
        version: int,
        config_version: int,
        handler_version: int,
        title: str,
        description: str,
        category: str,
        handler: str,
        input_ports: list[PortSpec] = [],
        output_ports: list[PortSpec] = [],
        config_schema: list[ConfigFieldSpec] = [],
        permissions: list[str] = [],
        connector_requirements: list[ConnectorRequirementSpec] = [],
        retry_policy: RetryPolicySpec = RetryPolicySpec(),
        effect_policy: EffectPolicySpec = EffectPolicySpec(),
        audit_fields: list[str] = [],
        is_trigger: bool = False,
        allow_multiple: bool = False;
}

obj ResourceScopeSpec {
    has connector_id: str,
        permission: str,
        mode: str,
        target: str = "",
        access: str = "";
}

obj CompilerProvenanceSpec {
    has mode: str = "deterministic",
        compiler_id: str = "quaze.golden-workflow",
        compiler_version: str = "2",
        fallback_reason: str = "",
        outbound_data: list[str] = [];
}

obj RunContractSpec {
    has state: str = "unavailable",
        enforcement_level: str = "experimental",
        contract_id: str = "",
        contract_snapshot_hash: str = "",
        workflow_version: int = 0,
        workflow_revision_digest: str = "",
        connector_mode: str = "",
        read_count: int = 0,
        transform_count: int = 0,
        approval_count: int = 0,
        write_count: int = 0,
        open_count: int = 0,
        send_count: int = 0,
        delete_count: int = 0,
        purchase_count: int = 0,
        maximum_affected_items: int = 0,
        required_permissions: list[str] = [],
        resource_scopes: list[ResourceScopeSpec] = [],
        outbound_data: list[str] = [],
        required_approvals: list[str] = [],
        retry_policy: list[str] = [],
        duplicate_protection: str = "",
        irreversible_effects: list[str] = [],
        blockers: list[str] = [];
}

obj EffectProposalSpec {
    has state: str = "not_prepared",
        change_kind: str = "",
        content_visibility: str = "redacted",
        digest_version: str = "",
        contract_id: str = "",
        effect_id: str = "",
        block_id: str = "",
        block_type: str = "",
        workflow_version: int = 0,
        workflow_revision_digest: str = "",
        block_version: int = 0,
        config_version: int = 0,
        handler_version: int = 0,
        connector_id: str = "",
        connector_implementation_version: int = 0,
        connector_mode: str = "",
        approval_generation: int = 0,
        approval_nonce: str = "",
        target: str = "",
        target_fingerprint: str = "",
        prior_target_hash: str = "",
        proposed_payload_hash: str = "",
        proposed_content_excerpt: str = "",
        proposed_content_truncated: bool = False,
        diff_excerpt: str = "",
        diff_truncated: bool = False,
        source_references: list[str] = [],
        source_references_hash: str = "",
        evidence_snapshot_hashes: list[str] = [],
        remaining_effects: list[str] = [],
        approval_allowed: bool = False,
        blockers: list[str] = [],
        effect_digest: str = "";
}

obj RunReceiptSpec {
    has state: str = "not_available",
        run_id: str = "",
        approved_digest: str = "",
        contract_snapshot_hash: str = "",
        planned_effects: list[str] = [],
        performed_effects: list[str] = [],
        deviations: list[str] = [],
        planned_read_count: int = 0,
        performed_read_count: int = 0,
        planned_write_count: int = 0,
        performed_write_count: int = 0,
        planned_open_count: int = 0,
        performed_open_count: int = 0,
        open_disposition: str = "not_planned",
        open_reason: str = "",
        planned_send_count: int = 0,
        performed_send_count: int = 0,
        planned_delete_count: int = 0,
        performed_delete_count: int = 0,
        planned_purchase_count: int = 0,
        performed_purchase_count: int = 0,
        retry_count: int = 0,
        duplicate_protection_state: str = "",
        effect_outcome: str = "",
        completed_at: str = "",
        artifact_path: str = "",
        artifact_hash: str = "",
        source_references: list[str] = [],
        compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec(),
        derived_from_persisted_state: bool = False;
}

obj BlockSpec {
    has id: str,
        block_type: str,
        title: str,
        block_version: int = 1,
        config_version: int = 1,
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
        validation: ValidationResult,
        compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec();
}

obj ConnectorResult {
    has success: bool,
        data: dict[str, object] = {},
        evidence_summary: str = "",
        error: str = "",
        connector_id: str = "",
        mode: str = "",
        status: str = "unavailable",
        error_code: str = "",
        retryable: bool = False;
}

obj RunStepSpec {
    has id: str,
        block_id: str,
        title: str,
        block_type: str = "",
        block_version: int = 1,
        config_version: int = 1,
        state: StepState = StepState.PENDING,
        attempt: int = 0,
        retry_state: str = "not_requested",
        started_at: str = "",
        completed_at: str = "",
        evidence_summary: str = "",
        evidence_snapshot_hashes: list[str] = [],
        planned_effect: EffectKind = EffectKind.NONE,
        performed_effect: EffectKind = EffectKind.NONE,
        effect_digest: str = "",
        error: str = "";
}

obj ApprovalSpec {
    has id: str = "",
        run_id: str = "",
        state: str = "not_requested",
        prompt: str = "",
        effect_digest: str = "",
        nonce: str = "",
        generation: int = 0,
        decision_digest: str = "",
        decision_nonce: str = "",
        decision_request_id: str = "",
        stale_reason: str = "",
        requested_at: str = "",
        decided_at: str = "";
}

obj ApprovalDecisionOutcomeSpec {
    has state: str = "uncertain",
        run_id: str = "",
        decision_request_id: str = "",
        approved: bool = False,
        approval_generation: int = 0,
        effect_digest: str = "",
        approval_nonce: str = "",
        message: str = "";
}

obj ArtifactSpec {
    has id: str = "",
        run_id: str = "",
        path: str = "",
        content_hash: str = "",
        effect_digest: str = "",
        write_state: str = "",
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
        block_catalog: list[BlockDefinitionSpec] = [],
        run_contract: RunContractSpec = RunContractSpec(),
        effect_proposal: EffectProposalSpec = EffectProposalSpec(),
        receipt: RunReceiptSpec = RunReceiptSpec(),
        compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec(),
        approval_outcome: ApprovalDecisionOutcomeSpec = ApprovalDecisionOutcomeSpec(),
        compiler_mode: str = "deterministic",
        compiler_notice: str = "";
}

node Workflow {
    has workflow_id: str,
        name: str,
        version: int = 1,
        created_at: str = "",
        revision_digest: str = "",
        compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec(),
        validation_state: str = "unvalidated",
        validation_errors: list[str] = [],
        validation_warnings: list[str] = [];
}

node Block {
    has block_id: str,
        block_type: str,
        title: str,
        position: int,
        block_version: int = 1,
        config_version: int = 1,
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
        workflow_version: int = 1,
        idempotency_key: str = "",
        cancel_requested: bool = False,
        recovered_at: str = "",
        recovery_count: int = 0,
        retry_count: int = 0,
        approval_generation: int = 0,
        connector_mode: str = "fixture",
        compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec(),
        approval_decision_requests: dict[str, str] = {},
        last_approval_outcome: ApprovalDecisionOutcomeSpec = ApprovalDecisionOutcomeSpec(),
        run_contract: RunContractSpec = RunContractSpec(),
        effect_proposal: EffectProposalSpec = EffectProposalSpec(),
        receipt: RunReceiptSpec = RunReceiptSpec(),
        contract_snapshot: str = "",
        contract_snapshot_hash: str = "",
        context: dict[str, object] = {};
}

node RunStep {
    has step_id: str,
        block_id: str,
        title: str,
        position: int,
        block_type: str = "",
        block_version: int = 1,
        config_version: int = 1,
        idempotency_key: str = "",
        state: StepState = StepState.PENDING,
        attempt: int = 0,
        retry_state: str = "not_requested",
        started_at: str = "",
        completed_at: str = "",
        evidence_summary: str = "",
        outputs: dict[str, object] = {},
        evidence_snapshot_hashes: list[str] = [],
        planned_effect: EffectKind = EffectKind.NONE,
        performed_effect: EffectKind = EffectKind.NONE,
        effect_digest: str = "",
        error: str = "";
}

node Approval {
    has approval_id: str,
        run_id: str,
        state: str = "requested",
        prompt: str = "",
        effect_digest: str = "",
        nonce: str = "",
        generation: int = 0,
        decision_digest: str = "",
        decision_nonce: str = "",
        decision_request_id: str = "",
        stale_reason: str = "",
        requested_at: str = "",
        decided_at: str = "";
}

node Artifact {
    has artifact_id: str,
        run_id: str,
        path: str,
        content_hash: str = "",
        effect_digest: str = "",
        write_state: str = "",
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
    has position: int,
        source_port: str = "",
        target_port: str = "";
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
