"""Persistent graph lifecycle tests."""

import from contracts {
    Approval,
    Block,
    CitesEvidence,
    ConnectionSpec,
    EffectKind,
    HasRun,
    HasEvidence,
    HasStep,
    ProducedArtifact,
    Run,
    RunState,
    RunStep,
    StepState,
    StepForBlock,
    ValidationResult,
    CompilerProvenanceSpec,
    ContainsBlock,
    Workflow
}
import from safety { sanitize_public_message }
import from workflow { golden_workflow_spec }


def _run_at_review -> Run {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    draft_step = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "draft-brief"
    ][0];
    persist_step_output(
        run,
        draft_step,
        {
            "brief_markdown": "# Synthetic fixture brief\n",
            "source_references": ["fixture://synthetic-source"]
        },
        ["synthetic-evidence-hash"],
        EffectKind.TRANSFORM
    );
    draft_step.state = StepState.SUCCEEDED;
    approval_step = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ][0];
    request_approval(run, approval_step, "Review the synthetic fixture draft.");
    assert run.state == RunState.AWAITING_APPROVAL;
    return run;
}


def _contract_step(run: Run, block_id: str) -> RunStep {
    matches = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == block_id
    ];
    assert len(matches) == 1;
    return matches[0];
}


def _contract_block(run: Run, block_id: str) -> Block {
    step = _contract_step(run, block_id);
    matches = [step->:StepForBlock:->];
    assert len(matches) == 1;
    return matches[0];
}


def _approve_latest_review(run: Run) -> Approval {
    outcome_state = "";
    for attempt in range(3) {
        approval = [run->:RequiresApproval:->][0];
        outcome = decide_approval(
            run,
            True,
            approval.effect_digest,
            approval.nonce,
            "decision-" + str(approval.generation) + "-" + str(attempt)
        );
        outcome_state = outcome.state;
        if outcome.state == "accepted" {
            break;
        }
    }
    assert outcome_state == "accepted";
    return [run->:RequiresApproval:->][0];
}


def _parent_format_legacy_run -> Run {
    workflow = root ++> Workflow(
        workflow_id="legacy-parent-workflow",
        name="Parent format workflow",
        version=1,
        created_at="2026-01-01T00:00:00+00:00",
        revision_digest="",
        compiler_provenance=CompilerProvenanceSpec(
            mode="legacy",
            compiler_id="quaze.parent-format",
            compiler_version="1"
        )
    );
    save_block = Block(
        block_id="save-brief",
        block_type="save_brief",
        title="Save Brief",
        position=0,
        block_version=1,
        config_version=1,
        config={"filename": "Tomorrow Brief.md"}
    );
    workflow +>:ContainsBlock(position=0):+> save_block;
    run = Run(
        run_id="legacy-parent-run",
        workflow_id=workflow.workflow_id,
        workflow_version=1,
        state=RunState.RUNNING,
        connector_mode="fixture",
        context={"approved_brief": "# Legacy content\n"}
    );
    workflow +>:HasRun:+> run;
    step = RunStep(
        step_id="legacy-save-step",
        block_id=save_block.block_id,
        title=save_block.title,
        position=0,
        block_type=save_block.block_type,
        block_version=save_block.block_version,
        config_version=save_block.config_version,
        state=StepState.PENDING,
        planned_effect=EffectKind.WRITE
    );
    run +>:HasStep(position=0):+> step;
    step +>:StepForBlock:+> save_block;
    return run;
}

test "materializes the seven-block Jac graph" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    blocks = [workflow->:ContainsBlock:->];
    assert len(blocks) == 7;
    assert len([blocks[0]->:ExecutionFlow:->]) == 1;
}

test "creates a persisted run step for every block" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    assert len([run->:HasStep:->]) == 7;
    assert run.state == RunState.RUNNING;
}

test "approval pauses and resumes the same run" {
    run = _run_at_review();
    approval_steps = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ];
    approval = [run->:RequiresApproval:->][0];
    paused_run_id = run.run_id;
    assert approval.state == "requested";
    assert run.state == RunState.AWAITING_APPROVAL;
    _approve_latest_review(run);
    assert run.run_id == paused_run_id;
    assert run.state == RunState.RUNNING;
    assert approval_steps[0].state == StepState.SUCCEEDED;
}

test "repeated approval decision is idempotent" {
    run = _run_at_review();
    approval = _approve_latest_review(run);
    first = run.last_approval_outcome;
    request_id = first.decision_request_id;
    record = run.approval_decision_requests.get(request_id);
    repeated = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        request_id
    );
    assert str(repeated) == str(first);
    assert repeated.state == "accepted";
    assert run.approval_decision_requests.get(request_id) == record;
    assert len([run->:RequiresApproval:->]) == 1;
}


test "decision replay is immutable across conflicts and empty request IDs" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    request_id = "immutable-decision";
    accepted = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        request_id
    );
    record = run.approval_decision_requests.get(request_id);
    assert accepted.state == "accepted";
    assert isinstance(record, str);

    conflict = decide_approval(
        run,
        False,
        approval.effect_digest,
        approval.nonce,
        request_id
    );
    assert conflict.state == "uncertain";
    assert run.approval_decision_requests.get(request_id) == record;
    assert run.last_approval_outcome == accepted;

    changed_digest = decide_approval(
        run,
        True,
        "different-digest",
        approval.nonce,
        request_id
    );
    assert changed_digest.state == "uncertain";
    assert run.approval_decision_requests.get(request_id) == record;
    assert run.last_approval_outcome == accepted;

    changed_nonce = decide_approval(
        run,
        True,
        approval.effect_digest,
        "different-nonce",
        request_id
    );
    assert changed_nonce.state == "uncertain";
    assert run.approval_decision_requests.get(request_id) == record;
    assert run.last_approval_outcome == accepted;

    empty = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        ""
    );
    assert empty.state == "uncertain";
    assert run.last_approval_outcome == accepted;
    assert "" not in run.approval_decision_requests;
}

test "workflow revisions preserve historical run provenance" {
    original = golden_workflow_spec();
    original_node = materialize_workflow(original, ValidationResult(valid=True));
    run = create_run_graph(original_node, original, "fixture");

    revised = golden_workflow_spec();
    revised.version = 3;
    moved = revised.blocks[2];
    revised.blocks[2] = revised.blocks[3];
    revised.blocks[3] = moved;
    revised.connections = [];
    for position in range(len(revised.blocks) - 1) {
        revised.connections.append(
            ConnectionSpec(
                source_id=revised.blocks[position].id,
                target_id=revised.blocks[position + 1].id
            )
        );
    }
    revised.validation = ValidationResult(
        valid=False,
        errors=["Revision intentionally reordered for provenance testing."]
    );
    materialize_workflow(revised, revised.validation);

    persisted = run_to_demo_state(run);
    assert persisted.workflow.version == 2;
    assert [block.id for block in persisted.workflow.blocks] == [
        block.id for block in original.blocks
    ];
    assert len([run->:HasStep:->]) == 7;
}

test "legacy version one stays readable and cannot execute as version two" {
    legacy = golden_workflow_spec();
    legacy.version = 1;
    legacy.compiler_provenance = CompilerProvenanceSpec(
        mode="legacy",
        compiler_id="quaze.parent-format",
        compiler_version="1"
    );
    legacy_node = materialize_workflow(legacy, ValidationResult(valid=True));
    persisted_legacy = workflow_to_spec(legacy_node);
    assert persisted_legacy.version == 1;
    assert persisted_legacy.compiler_provenance.mode == "legacy";

    legacy_run_rejected = False;
    try {
        create_run_graph(legacy_node, legacy, "fixture");
    } except ValueError as _error {
        legacy_run_rejected = True;
    }
    assert legacy_run_rejected;

    current = golden_workflow_spec();
    current_node = materialize_workflow(current, ValidationResult(valid=True));
    current_run = create_run_graph(current_node, current, "fixture");
    assert current_run.workflow_version == 2;
    assert workflow_to_spec(legacy_node).version == 1;
}


test "parent-format persisted legacy runs stay read only at lifecycle gates" {
    run = _parent_format_legacy_run();
    step = _contract_step(run, "save-brief");
    outcome = decide_approval(
        run, True, "legacy-digest", "legacy-nonce", "legacy-decision"
    );
    assert outcome.state == "stale";
    assert "read-only" in outcome.message;
    assert "legacy-decision" not in run.approval_decision_requests;
    assert not recover_persisted_run(run);
    assert run.recovery_count == 0;
    assert step.state == StepState.PENDING;
    assert step.attempt == 0;
    assert len([run->:ProducedArtifact:->]) == 0;
    state = run_to_demo_state(run);
    assert state.run_contract.state == "unavailable";
    assert any("Legacy workflow contracts" in blocker
        for blocker in state.run_contract.blockers);

    run.state = RunState.FAILED;
    step.state = StepState.FAILED;
    step.attempt = 1;
    step.retry_state = "available";
    assert not prepare_failed_run_retry(run);
    assert run.retry_count == 0;
    assert step.retry_state == "available";
}

test "execution flow ports round trip exactly" {
    spec = golden_workflow_spec();
    spec.version = 22;
    spec.connections[0].source_port = "custom_allowed_output";
    spec.connections[0].target_port = "custom_allowed_input";
    spec.blocks[0].outputs.append("custom_allowed_output");
    spec.blocks[1].inputs.append("custom_allowed_input");
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    persisted = workflow_to_spec(workflow);
    assert persisted.connections[0].source_port == "custom_allowed_output";
    assert persisted.connections[0].target_port == "custom_allowed_input";
}

test "terminal approval cannot be reopened" {
    run = _run_at_review();
    approval_step = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ][0];
    approval = _approve_latest_review(run);
    evidence_count = len([approval_step->:HasEvidence:->]);

    repeated = request_approval(run, approval_step, "Review again.");
    assert repeated == approval;
    assert repeated.state == "approved";
    assert run.state == RunState.RUNNING;
    assert len([approval_step->:HasEvidence:->]) == evidence_count;
}

test "persisted validation keeps actionable findings" {
    spec = golden_workflow_spec();
    spec.version = 3;
    validation = ValidationResult(
        valid=False,
        errors=["Save Brief must be immediately preceded by Approval."],
        warnings=["Obsidian is unavailable."]
    );
    workflow = materialize_workflow(spec, validation);
    persisted = workflow_to_spec(workflow);
    assert persisted.validation.errors == validation.errors;
    assert persisted.validation.warnings == validation.warnings;
}

test "artifact attachment is canonical and idempotent" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    save_step = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "save-brief"
    ][0];
    record_step_event(run, save_step, "artifact_saved", "Saved once.");
    artifact = attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        "hash-one",
        ["fixture-calendar://apex-design-review"]
    );
    record_step_event(run, save_step, "artifact_reused", "Reused once.");
    repeated = attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        "hash-one",
        ["fixture-calendar://apex-design-review"]
    );
    assert repeated == artifact;
    assert len([run->:ProducedArtifact:->]) == 1;
    assert len([artifact->:CitesEvidence:->]) == 2;
}


test "server approval pair and canonical snapshot are persisted" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    assert approval.effect_digest != "";
    assert approval.nonce.startswith("approval-nonce-");
    assert run.contract_snapshot_hash == approval.effect_digest;
    assert run.run_contract.contract_snapshot_hash == approval.effect_digest;
    assert '"domain":"quaze.effect-contract.v1"' in run.contract_snapshot;
    assert '"run_id":"' + run.run_id + '"' in run.contract_snapshot;
    assert '"approval_nonce":"' + approval.nonce + '"' in run.contract_snapshot;
    assert '"workflow_block_contracts":' in run.contract_snapshot;
    assert '"connector_execution_modes":' in run.contract_snapshot;
}


test "missing or mismatched approval pair fails closed" {
    run = _run_at_review();
    original = [run->:RequiresApproval:->][0];
    original_generation = original.generation;
    original_nonce = original.nonce;
    missing = decide_approval(run, True, "", "", "missing-pair");
    assert missing.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.state == "requested";
    assert refreshed.generation == original_generation + 1;
    assert refreshed.nonce != original_nonce;
    assert refreshed.stale_reason != "";
    assert _contract_step(run, "save-brief").attempt == 0;
    assert len([run->:ProducedArtifact:->]) == 0;

    digest = refreshed.effect_digest;
    nonce = refreshed.nonce;
    wrong = decide_approval(
        run, True, digest, "client-defined-nonce", "wrong-pair"
    );
    assert wrong.state == "stale";
    second_refresh = [run->:RequiresApproval:->][0];
    assert second_refresh.nonce != nonce;
    assert second_refresh.stale_reason != "";
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "workflow version mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    workflows = [run<-:HasRun:<-];
    workflows[0].version += 1;
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "workflow-version-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation;
    assert run_to_demo_state(run).run_contract.state == "unavailable";
    assert "read-only" in outcome.message;
}


test "block config mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    save_block = _contract_block(run, "save-brief");
    save_block.config["filename"] = "mutated-after-review.md";
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "config-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation + 1;
    assert refreshed.stale_reason != "";
}


test "persisted draft mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["brief_markdown"] = "# Changed after review\n";
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "draft-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation + 1;
    assert refreshed.stale_reason != "";
}

test "source reference mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    original_source_hash = run.effect_proposal.source_references_hash;
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["source_references"] = [
        "fixture://changed-source-only"
    ];
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "source-reference-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation + 1;
    assert run.effect_proposal.source_references_hash != original_source_hash;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "evidence snapshot mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    draft_step = _contract_step(run, "draft-brief");
    draft_step.evidence_snapshot_hashes.append("mutated-evidence-hash");
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "evidence-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation + 1;
    assert refreshed.stale_reason != "";
}


test "canonical snapshot mutation invalidates displayed approval" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    run.contract_snapshot = run.contract_snapshot + "tampered";
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "snapshot-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == prior_generation + 1;
    assert refreshed.stale_reason != "";
}


test "connector mode mutation invalidates and redacts review content" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    run.connector_mode = "live";
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "connector-mode-mutation"
    );
    assert outcome.state == "stale";
    refreshed = [run->:RequiresApproval:->][0];
    assert refreshed.generation == approval.generation;
    assert refreshed.stale_reason == "";
    assert "read-only" in outcome.message;
    assert run_to_demo_state(run).run_contract.state == "unavailable";
    assert len([run->:ProducedArtifact:->]) == 0;
}

test "oversized exact content is blocked by the server eligibility rule" {
    run = _run_at_review();
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["brief_markdown"] = "# Fixture\n" + ("x" * 17000);
    assert refresh_stale_approval(run, "Fixture content changed.");
    approval = [run->:RequiresApproval:->][0];
    assert not run.effect_proposal.approval_allowed;
    assert run.effect_proposal.proposed_content_truncated;
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "truncated-content"
    );
    assert outcome.state == "stale";
    assert len([run->:ProducedArtifact:->]) == 0;
}

test "truncated exact diff is blocked by the server eligibility rule" {
    run = _run_at_review();
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["brief_markdown"] = "# Fixture\n" + ("y" * 13000);
    assert refresh_stale_approval(run, "Fixture diff changed.");
    approval = [run->:RequiresApproval:->][0];
    assert not run.effect_proposal.proposed_content_truncated;
    assert run.effect_proposal.diff_truncated;
    assert not run.effect_proposal.approval_allowed;
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "truncated-diff"
    );
    assert outcome.state == "stale";
    assert len([run->:ProducedArtifact:->]) == 0;
}



test "non-fixture artifact and receipt source views stay redacted" {
    run = _run_at_review();
    run.connector_mode = "live";
    raw_source = "vault://private-customer-note";
    attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        "persisted-artifact-hash",
        [raw_source],
        "approved-effect-digest",
        "create"
    );
    run.state = RunState.FAILED;
    run.updated_at = now_iso();
    derive_persisted_receipt(run);
    state = run_to_demo_state(run);
    assert raw_source not in state.artifact.source_references;
    assert raw_source not in state.receipt.source_references;
    assert all(
        source.startswith("source-sha256:")
        for source in state.artifact.source_references
    );
    assert all(
        source.startswith("source-sha256:")
        for source in state.receipt.source_references
    );
}


test "unavailable exact payload keeps review blocked without a digest" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    prior_generation = approval.generation;
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["brief_markdown"] = "";
    outcome = decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "empty-payload"
    );
    assert outcome.state == "stale";
    blocked = [run->:RequiresApproval:->][0];
    assert blocked.state == "requested";
    assert blocked.generation == prior_generation + 1;
    assert blocked.effect_digest == "";
    assert blocked.stale_reason != "";
    assert run.effect_proposal.state == "blocked";
    assert run.effect_proposal.proposed_content_excerpt == "";
    assert run.effect_proposal.diff_excerpt == "";
    assert run.contract_snapshot == "";
    assert _contract_step(run, "save-brief").attempt == 0;
}


test "exact blocked review can be rejected without an approval digest" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    draft_step = _contract_step(run, "draft-brief");
    draft_step.outputs["brief_markdown"] = "";
    decide_approval(
        run,
        True,
        approval.effect_digest,
        approval.nonce,
        "block-empty-review"
    );
    blocked = [run->:RequiresApproval:->][0];
    assert blocked.effect_digest == "";
    assert blocked.nonce != "";
    rejected = decide_approval(
        run,
        False,
        "",
        blocked.nonce,
        "reject-blocked-review"
    );
    assert rejected.state == "rejected";
    assert run.state == RunState.FAILED;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "same workflow id and version rejects changed content" {
    original = golden_workflow_spec();
    materialize_workflow(original, ValidationResult(valid=True));
    changed = golden_workflow_spec();
    changed.blocks[1].config["range"] = "changed";
    rejected = False;
    try {
        materialize_workflow(changed, ValidationResult(valid=True));
    } except ValueError as _error {
        rejected = True;
    }
    assert rejected;
}


test "post-approval restart rebuilds context before recovery" {
    run = _run_at_review();
    approval = _approve_latest_review(run);
    run.context = {"connector_mode": "fixture"};
    assert recover_persisted_run(run);
    brief = run.context.get("brief_markdown");
    assert isinstance(brief, str);
    assert brief.startswith("# Synthetic fixture brief");
    assert run.context.get("approved_brief") == brief;
    assert approval.state == "approved";
    assert run.recovery_count == 1;
    assert run.state == RunState.RUNNING;
}


test "recovery reconciles a persisted artifact before retry" {
    run = _run_at_review();
    approval = _approve_latest_review(run);
    save_step = _contract_step(run, "save-brief");
    save_step.state = StepState.RUNNING;
    attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        run.effect_proposal.proposed_payload_hash,
        run.effect_proposal.source_references,
        approval.effect_digest,
        "create"
    );
    assert recover_persisted_run(run);
    recovered_save = _contract_step(run, "save-brief");
    assert recovered_save.state == StepState.SUCCEEDED;
    assert recovered_save.retry_state == "reconciled";
    assert recovered_save.performed_effect == EffectKind.WRITE;
    assert len([run->:ProducedArtifact:->]) == 1;
}


test "open failure after persisted save produces a partial receipt" {
    run = _run_at_review();
    approval = _approve_latest_review(run);
    save_step = _contract_step(run, "save-brief");
    save_step.state = StepState.SUCCEEDED;
    save_step.performed_effect = EffectKind.WRITE;
    attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        run.effect_proposal.proposed_payload_hash,
        run.effect_proposal.source_references,
        approval.effect_digest,
        "create"
    );
    open_step = _contract_step(run, "open-result");
    open_step.state = StepState.FAILED;
    open_step.error = "Injected fixture open failure.";
    run.state = RunState.FAILED;
    run.updated_at = now_iso();
    receipt = derive_persisted_receipt(run);
    assert receipt.state == "partial";
    assert receipt.planned_write_count == 1;
    assert receipt.performed_write_count == 1;
    assert receipt.effect_outcome == "create";
    assert receipt.open_disposition == "failed";
    assert any(
        "open:open-result" in deviation
        for deviation in receipt.deviations
    );
    assert receipt.completed_at != "";
    assert receipt.derived_from_persisted_state;
}


test "no change receipt reports zero performed writes truthfully" {
    run = _run_at_review();
    approval = _approve_latest_review(run);
    save_step = _contract_step(run, "save-brief");
    save_step.state = StepState.SUCCEEDED;
    save_step.performed_effect = EffectKind.NONE;
    attach_artifact(
        run,
        "fixtures/demo-vault/Tomorrow Brief.md",
        run.effect_proposal.proposed_payload_hash,
        run.effect_proposal.source_references,
        approval.effect_digest,
        "no_change"
    );
    run.state = RunState.SUCCEEDED;
    run.updated_at = now_iso();
    receipt = derive_persisted_receipt(run);
    assert receipt.state == "complete";
    assert receipt.planned_write_count == 1;
    assert receipt.performed_write_count == 0;
    assert receipt.effect_outcome == "no_change";
    assert (
        receipt.duplicate_protection_state
        == "bounded_content_hash_matched_existing"
    );
    assert all(
        "write:save-brief" not in deviation
        for deviation in receipt.deviations
    );
}


test "cancellation is persisted and idempotent" {
    run = _run_at_review();
    assert cancel_persisted_run(run);
    assert run.state == RunState.CANCELED;
    assert run.cancel_requested;
    assert not cancel_persisted_run(run);
    assert run.receipt.state == "canceled";
    assert [run->:RequiresApproval:->][0].state == "canceled";
    assert run.receipt.completed_at != "";
    assert all(
        step.state in [
            StepState.SUCCEEDED,
            StepState.SKIPPED,
            StepState.CANCELED
        ]
        for step in [run->:HasStep:->]
    );
    assert len([run->:ProducedArtifact:->]) == 0;
}

test "canceled and uncertain approval outcomes are typed" {
    canceled_run = _run_at_review();
    canceled_approval = [canceled_run->:RequiresApproval:->][0];
    assert cancel_persisted_run(canceled_run);
    canceled = decide_approval(
        canceled_run,
        True,
        canceled_approval.effect_digest,
        canceled_approval.nonce,
        "decision-after-cancel"
    );
    assert canceled.state == "canceled";
    canceled_repeat = decide_approval(
        canceled_run,
        True,
        canceled_approval.effect_digest,
        canceled_approval.nonce,
        "decision-after-cancel"
    );
    assert canceled_repeat.state == "canceled";

    uncertain_run = _run_at_review();
    uncertain_approval = [uncertain_run->:RequiresApproval:->][0];
    uncertain = decide_approval(
        uncertain_run,
        True,
        uncertain_approval.effect_digest,
        uncertain_approval.nonce,
        ""
    );
    assert uncertain.state == "uncertain";
    assert uncertain_run.state == RunState.AWAITING_APPROVAL;
}

test "stale rejection cannot replace the current approval generation" {
    run = _run_at_review();
    prior = [run->:RequiresApproval:->][0];
    prior_digest = prior.effect_digest;
    prior_nonce = prior.nonce;
    assert refresh_stale_approval(run, "New review generation.");
    current = [run->:RequiresApproval:->][0];
    current_generation = current.generation;
    stale = decide_approval(
        run,
        False,
        prior_digest,
        prior_nonce,
        "stale-rejection"
    );
    assert stale.state == "stale";
    stale_repeat = decide_approval(
        run,
        False,
        prior_digest,
        prior_nonce,
        "stale-rejection"
    );
    assert stale_repeat.state == "stale";
    current_after = [run->:RequiresApproval:->][0];
    assert current_after.state == "requested";
    assert current_after.generation == current_generation;
    assert run.state == RunState.AWAITING_APPROVAL;
}

test "rejection returns a typed outcome and no effect" {
    run = _run_at_review();
    approval = [run->:RequiresApproval:->][0];
    rejected = decide_approval(
        run,
        False,
        approval.effect_digest,
        approval.nonce,
        "typed-rejection"
    );
    assert rejected.state == "rejected";
    assert run.receipt.state == "rejected_no_effect";
    assert len([run->:ProducedArtifact:->]) == 0;
}

test "target safety revalidation rotates review without an artifact" {
    target_run = _run_at_review();
    target_generation = target_run.approval_generation;
    assert refresh_stale_approval(
        target_run, "The target changed at the final write precondition."
    );
    assert target_run.approval_generation == target_generation + 1;
    assert len([target_run->:ProducedArtifact:->]) == 0;
}

test "connector errors are sanitized before persistence and presentation" {
    raw = (
        "Bearer secret-token https://example.test/file?X-Amz-Signature=secret "
        "/Users/demo/private/note.md\nMCP stderr: raw provider failure\x07"
    );
    sanitized = sanitize_public_message(raw);
    assert "secret-token" not in sanitized;
    assert "X-Amz-Signature" not in sanitized;
    assert "/Users/demo" not in sanitized;
    assert "\n" not in sanitized;
    assert "\x07" not in sanitized;
    assert "raw provider failure" not in sanitized;

    run = _run_at_review();
    step = _contract_step(run, "read-calendar");
    event = record_step_event(run, step, "connector_failed", raw);
    assert "secret-token" not in event.message;
    state = run_to_demo_state(run);
    assert all("secret-token" not in item.message for item in state.events);
}


test "absolute paths are root agnostic while slash prose is preserved" {
    raw_paths = [
        "/Library/ApplicationSupport/QuaZe/runtime.log",
        "/System/Volumes/Data/private.log",
        "/Applications/QuaZe.app/Contents/MacOS/QuaZe",
        "/opt/quaze/bin/runtime",
        "/Users/demo/private/note.md",
        "/private/tmp/quaze/run.log"
    ];
    message = (
        "read/write and approve/reject remain ordinary prose; "
        + " ".join(raw_paths)
    );
    sanitized = sanitize_public_message(message);
    assert "read/write" in sanitized;
    assert "approve/reject" in sanitized;
    assert all(path not in sanitized for path in raw_paths);
    assert sanitized.count("[path redacted]") == len(raw_paths);

    run = _run_at_review();
    step = _contract_step(run, "open-result");
    step.state = StepState.FAILED;
    step.error = "Open failed at /Applications/QuaZe.app/Contents/MacOS/QuaZe.";
    run.state = RunState.FAILED;
    receipt = derive_persisted_receipt(run);
    event = record_step_event(
        run,
        step,
        "connector_failed",
        "Trace at /System/Library/Frameworks/EventKit.framework/EventKit."
    );
    state = run_to_demo_state(run);
    assert "/Applications/" not in receipt.open_reason;
    assert "/System/" not in event.message;
    assert "/Applications/" not in state.receipt.open_reason;
    assert all("/System/" not in item.message for item in state.events);
}

test "failed and uncertain receipts remain distinct" {
    failed_run = _run_at_review();
    approval_step = _contract_step(failed_run, "approval");
    approval_step.state = StepState.FAILED;
    failed_run.state = RunState.FAILED;
    failed_run.updated_at = now_iso();
    failed_receipt = derive_persisted_receipt(failed_run);
    assert failed_receipt.state == "failed_no_effect";

    uncertain_run = _run_at_review();
    approval = _approve_latest_review(uncertain_run);
    save_step = _contract_step(uncertain_run, "save-brief");
    save_step.state = StepState.RUNNING;
    uncertain_run.state = RunState.RUNNING;
    uncertain_receipt = derive_persisted_receipt(uncertain_run);
    assert uncertain_receipt.state == "unknown/reconciliation_required";
    assert approval.state == "approved";
}


test "failed idempotent step exposes an explicit retry state" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    read_step = _contract_step(run, "read-calendar");
    read_step.state = StepState.FAILED;
    read_step.attempt = 1;
    read_step.retry_state = "available";
    run.state = RunState.FAILED;
    assert prepare_failed_run_retry(run);
    retried_step = _contract_step(run, "read-calendar");
    candidate_run = find_run(run.run_id);
    assert candidate_run is not None;
    retried_run: Run = candidate_run;
    assert retried_step.state == StepState.PENDING;
    assert retried_step.retry_state == "requested";
    assert retried_run.retry_count == 1;
    assert retried_run.state == RunState.RUNNING;
}
