"""Public walker integration and persisted-run lifecycle tests."""

import os;
import from block_registry {
    block_catalog,
    block_definition,
    execute_registered_block
}
import from contracts {
    Block,
    CompilerProvenanceSpec,
    DemoState,
    EffectKind,
    HasStep,
    ProducedArtifact,
    Run,
    RunState,
    RunStep,
    RunStepSpec,
    StepState
}
import from connectors { BRIEF_FILENAME, CalendarEvent }
import from run_contract { effect_is_declared, preflight_for_workflow }
import from workflow { golden_workflow_spec }


def _brief_path -> str {
    return os.path.join(
        os.getcwd(), "fixtures", "demo-vault", BRIEF_FILENAME
    );
}


def _remove_generated_brief {
    path = _brief_path();
    if os.path.exists(path) {
        os.remove(path);
    }
}


def _step(state: DemoState, block_id: str) -> RunStepSpec {
    matches = [
        step
        for step in state.run_steps
        if step.block_id == block_id
    ];
    assert len(matches) == 1;
    return matches[0];
}


test "public compile and reorder expose deterministic validation" {
    compiled = compile_prompt(
        prompt="Prepare tomorrow's meeting brief and ask before saving."
    );
    compiled spawn root;
    assert len(compiled.reports) == 1;
    compiled_state = compiled.reports[0];
    assert compiled_state.validation.valid;
    assert len(compiled_state.workflow.blocks) == 7;
    assert compiled_state.workflow.version == 2;
    assert compiled_state.compiler_provenance.mode == "deterministic";

    reordered = reorder_blocks(
        workflow=compiled_state.workflow, block_id="approval", direction="down"
    );
    reordered spawn root;
    reordered_state = reordered.reports[0];
    assert not reordered_state.validation.valid;
    assert (
        "Save Brief must be immediately preceded by Approval." in reordered_state.validation.errors
    );
    assert reordered_state.compiler_provenance.mode == "deterministic";
}

test "typed compiler provenance survives validate reorder run refresh and receipt" {
    modes = ["hosted", "deterministic", "deterministic_fallback"];
    for (index, mode) in enumerate(modes) {
        spec = golden_workflow_spec();
        spec.version = 30 + index;
        spec.compiler_provenance = CompilerProvenanceSpec(
            mode=mode,
            compiler_id=(
                "jac.byllm" if mode == "hosted" else "quaze.golden-workflow"
            ),
            compiler_version="2",
            fallback_reason=(
                "hosted_unavailable"
                    if mode == "deterministic_fallback"
                    else ""
            ),
            outbound_data=(
                ["Prompt text was sent to the configured hosted compiler."]
                    if mode == "hosted"
                    else []
            )
        );
        validated = validate_workflow(workflow=spec);
        validated spawn root;
        validated_state = validated.reports[0];
        assert validated_state.compiler_provenance.mode == mode;
        assert validated_state.workflow.compiler_provenance.mode == mode;

        reordered = reorder_blocks(
            workflow=validated_state.workflow,
            block_id="run-now",
            direction="up"
        );
        reordered spawn root;
        reordered_state = reordered.reports[0];
        assert reordered_state.compiler_provenance.mode == mode;

        started = start_run(
            workflow=reordered_state.workflow,
            connector_mode="fixture"
        );
        started spawn root;
        run_state = started.reports[0];
        assert run_state.compiler_provenance.mode == mode;
        assert run_state.compiler_mode == mode;
        assert run_state.compiler_provenance.compiler_id != "";
        assert "Prepare" not in run_state.compiler_provenance.fallback_reason;

        refreshed = get_run(run_id=run_state.run_id);
        refreshed spawn root;
        refreshed_state = refreshed.reports[0];
        assert refreshed_state.compiler_provenance.mode == mode;

        canceled = cancel_run(run_id=run_state.run_id);
        canceled spawn root;
        receipt_state = canceled.reports[0];
        assert receipt_state.receipt.state == "canceled";
        assert receipt_state.receipt.compiler_provenance.mode == mode;
    }
}


test "public lifecycle pauses resumes same run and reuses artifact" {
    _remove_generated_brief();
    try {
        started = start_run(workflow=golden_workflow_spec(), connector_mode="fixture");
        started spawn root;
        paused = started.reports[0];
        assert paused.run_state == RunState.AWAITING_APPROVAL;
        assert paused.run_id != "";
        assert _step(paused, "draft-brief").state == StepState.SUCCEEDED;
        assert _step(paused, "approval").state == StepState.AWAITING_APPROVAL;
        assert _step(paused, "save-brief").state == StepState.PENDING;
        assert paused.artifact.path == "";
        assert not os.path.exists(_brief_path());
        assert paused.run_contract.read_count == 2;
        assert paused.run_contract.write_count == 1;
        assert paused.run_contract.send_count == 0;
        assert paused.run_contract.delete_count == 0;
        assert paused.run_contract.purchase_count == 0;
        assert paused.run_contract.enforcement_level == "experimental";
        assert paused.effect_proposal.state == "ready";
        assert paused.effect_proposal.approval_allowed;
        assert (
            paused.effect_proposal.content_visibility
            == "full_synthetic_fixture"
        );
        assert paused.effect_proposal.target == (
            "fixtures/demo-vault/Tomorrow Brief.md"
        );
        assert paused.effect_proposal.prior_target_hash == "absent";
        assert paused.effect_proposal.proposed_payload_hash != "";
        assert paused.effect_proposal.effect_digest == (
            paused.approval.effect_digest
        );
        assert paused.effect_proposal.approval_nonce == paused.approval.nonce;
        assert paused.effect_proposal.proposed_content_excerpt.startswith(
            "# Tomorrow Brief"
        );
        assert all(
            "# Tomorrow Brief" not in event.message
            for event in paused.events
        );
        paused_run_id = paused.run_id;

        candidate_run = find_run(paused_run_id);
        assert candidate_run is not None;
        persisted_run: Run = candidate_run;
        persisted_steps: list[RunStep] = [persisted_run->:HasStep:->];
        persisted_draft = [
            step for step in persisted_steps if step.block_id == "draft-brief"
        ][0];
        persisted_calendar = [
            step for step in persisted_steps if step.block_id == "read-calendar"
        ][0];
        persisted_vault = [
            step for step in persisted_steps if step.block_id == "search-vault"
        ][0];
        assert "brief_markdown" in persisted_draft.outputs;
        assert "meetings" in persisted_calendar.outputs;
        assert "matched_notes" in persisted_vault.outputs;

        loaded = get_run(run_id=paused_run_id);
        loaded spawn root;
        assert loaded.reports[0].run_id == paused_run_id;
        assert loaded.reports[0].run_state == RunState.AWAITING_APPROVAL;

        approved = approve_run(
            run_id=paused_run_id,
            approved=True,
            effect_digest=paused.approval.effect_digest,
            approval_nonce=paused.approval.nonce,
            decision_request_id="client-golden-approval"
        );
        approved spawn root;
        persisted_decision = approved.reports[0];
        assert persisted_decision.run_id == paused_run_id;
        assert persisted_decision.run_state == RunState.RUNNING;
        assert persisted_decision.approval_outcome.state == "accepted";
        assert persisted_decision.artifact.path == "";
        assert not os.path.exists(_brief_path());
        assert _step(persisted_decision, "save-brief").attempt == 0;

        refreshed_after_decision = get_run(run_id=paused_run_id);
        refreshed_after_decision spawn root;
        recovered_decision = refreshed_after_decision.reports[0];
        assert recovered_decision.approval.state == "approved";
        assert recovered_decision.approval_outcome.state == "accepted";
        assert recovered_decision.run_state == RunState.RUNNING;
        assert recovered_decision.artifact.path == "";
        persisted_run.context = {};

        resumed = recover_run(run_id=paused_run_id);
        resumed spawn root;
        completed = resumed.reports[0];
        assert completed.run_id == paused_run_id;
        assert completed.run_state == RunState.SUCCEEDED;
        assert _step(completed, "save-brief").state == StepState.SUCCEEDED;
        assert _step(completed, "save-brief").attempt == 1;
        assert _step(completed, "open-result").state == StepState.SKIPPED;
        assert completed.artifact.path == (
            "fixtures/demo-vault/Tomorrow Brief.md"
        );
        assert completed.artifact.content_hash != "";
        assert completed.artifact.effect_digest == paused.approval.effect_digest;
        assert len(completed.artifact.source_references) == 4;
        assert completed.approval.state == "approved";
        assert completed.approval.decision_digest == (
            paused.approval.effect_digest
        );
        assert completed.receipt.state == "complete";
        assert completed.receipt.planned_read_count == 2;
        assert completed.receipt.performed_read_count == 2;
        assert completed.receipt.planned_write_count == 1;
        assert completed.receipt.performed_write_count == 1;
        assert completed.receipt.planned_send_count == 0;
        assert completed.receipt.planned_delete_count == 0;
        assert completed.receipt.planned_purchase_count == 0;
        assert completed.receipt.deviations == [];
        assert completed.receipt.approved_digest == (
            paused.approval.effect_digest
        );
        assert (
            completed.receipt.duplicate_protection_state
            == "bounded_single_artifact_record_unverified_replay"
        );
        assert completed.receipt.planned_open_count == 1;
        assert completed.receipt.performed_open_count == 0;
        assert completed.receipt.open_disposition == "skipped_by_profile";
        assert completed.receipt.completed_at != "";
        assert completed.receipt.derived_from_persisted_state;
        event_count = len(completed.events);
        artifact_id = completed.artifact.id;

        repeated_resume = recover_run(run_id=paused_run_id);
        repeated_resume spawn root;
        repeated_resume_state = repeated_resume.reports[0];
        assert repeated_resume_state.artifact.id == artifact_id;
        assert _step(repeated_resume_state, "save-brief").attempt == 1;
        assert len(repeated_resume_state.events) == event_count;

        repeated = approve_run(
            run_id=paused_run_id,
            approved=True,
            effect_digest=paused.approval.effect_digest,
            approval_nonce=paused.approval.nonce,
            decision_request_id="client-golden-approval"
        );
        repeated spawn root;
        repeated_state = repeated.reports[0];
        assert repeated_state.run_id == paused_run_id;
        assert (
            repeated_state.approval_outcome.state
            == "accepted"
        );
        assert repeated_state.artifact.id == artifact_id;
        assert (
            repeated_state.artifact.content_hash == completed.artifact.content_hash
        );
        assert _step(repeated_state, "save-brief").attempt == 1;
        assert len(repeated_state.events) == event_count;

        markdown = open(_brief_path(), encoding="utf-8").read();
        assert "fixture-calendar://apex-design-review" in markdown;
        assert "fixture-calendar://maya-onboarding" in markdown;
        assert "vault://Apex%20Project.md" in markdown;
        assert "vault://Maya%20People.md" in markdown;
        assert "Missing context:" in markdown;
        assert "Weekend Errands" not in markdown;
    } finally {
        _remove_generated_brief();
    }
}


test "public rejection ends the run without an artifact" {
    started = start_run(workflow=golden_workflow_spec(), connector_mode="fixture");
    started spawn root;
    paused = started.reports[0];

    rejected = approve_run(
        run_id=paused.run_id,
        approved=False,
        effect_digest=paused.approval.effect_digest,
        approval_nonce=paused.approval.nonce,
        decision_request_id="client-rejection"
    );
    rejected spawn root;
    stopped = rejected.reports[0];
    assert stopped.run_id == paused.run_id;
    assert stopped.run_state == RunState.FAILED;
    assert stopped.approval.state == "rejected";
    assert _step(stopped, "save-brief").state == StepState.PENDING;
    assert stopped.artifact.path == "";
    assert stopped.approval_outcome.state == "rejected";
    assert stopped.receipt.state == "rejected_no_effect";
    assert stopped.receipt.performed_write_count == 0;
}


test "public rejection accepts the exact blocked generation without a digest" {
    started = start_run(workflow=golden_workflow_spec(), connector_mode="fixture");
    started spawn root;
    paused = started.reports[0];
    candidate = find_run(paused.run_id);
    assert candidate is not None;
    run: Run = candidate;
    draft_steps = [
        step for step in [run->:HasStep:->] if step.block_id == "draft-brief"
    ];
    draft_steps[0].outputs["brief_markdown"] = "";

    blocked_request = approve_run(
        run_id=paused.run_id,
        approved=True,
        effect_digest=paused.approval.effect_digest,
        approval_nonce=paused.approval.nonce,
        decision_request_id="public-block-empty-review"
    );
    blocked_request spawn root;
    blocked = blocked_request.reports[0];
    assert blocked.approval_outcome.state == "stale";
    assert blocked.approval.effect_digest == "";
    assert blocked.approval.nonce != "";

    rejected_request = approve_run(
        run_id=paused.run_id,
        approved=False,
        effect_digest="",
        approval_nonce=blocked.approval.nonce,
        decision_request_id="public-reject-blocked-review"
    );
    rejected_request spawn root;
    rejected = rejected_request.reports[0];
    assert rejected.approval_outcome.state == "rejected";
    assert rejected.run_state == RunState.FAILED;
    assert rejected.artifact.path == "";
}


test "public recovery and retry keep approved live runs read only" {
    started = start_run(workflow=golden_workflow_spec(), connector_mode="fixture");
    started spawn root;
    paused = started.reports[0];
    approved_request = approve_run(
        run_id=paused.run_id,
        approved=True,
        effect_digest=paused.approval.effect_digest,
        approval_nonce=paused.approval.nonce,
        decision_request_id="live-gate-approval"
    );
    approved_request spawn root;
    candidate = find_run(paused.run_id);
    assert candidate is not None;
    run: Run = candidate;
    run.connector_mode = "live";
    save_step = [
        step for step in [run->:HasStep:->] if step.block_id == "save-brief"
    ][0];

    recovered = recover_run(run_id=run.run_id);
    recovered spawn root;
    recovered_state = recovered.reports[0];
    assert recovered_state.run_contract.state == "unavailable";
    assert save_step.attempt == 0;
    assert len([run->:ProducedArtifact:->]) == 0;

    run.state = RunState.FAILED;
    save_step.state = StepState.FAILED;
    save_step.attempt = 1;
    save_step.retry_state = "available";
    retried = retry_run(run_id=run.run_id);
    retried spawn root;
    retried_state = retried.reports[0];
    assert retried_state.run_contract.state == "unavailable";
    assert run.retry_count == 0;
    assert save_step.attempt == 1;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "live connector mode is explicitly unavailable before creating a run" {
    stopped = start_run(
        workflow=golden_workflow_spec(), connector_mode="live"
    );
    stopped spawn root;
    state = stopped.reports[0];
    assert state.validation.valid;
    assert state.run_id == "";
    assert state.artifact.path == "";
    assert state.effect_proposal.state == "not_prepared";
    assert state.run_contract.state == "unavailable";
    assert state.run_contract.connector_mode == "fixture";
    assert any("Live execution is unavailable" in blocker
        for blocker in state.run_contract.blockers);
}


test "public start rejects changed content at the same workflow version" {
    original = golden_workflow_spec();
    validated = validate_workflow(workflow=original);
    validated spawn root;
    assert validated.reports[0].validation.valid;

    changed = golden_workflow_spec();
    changed.name = "Changed workflow name";
    stopped = start_run(workflow=changed, connector_mode="fixture");
    stopped spawn root;
    state = stopped.reports[0];
    assert not state.validation.valid;
    assert state.run_id == "";
    assert any(
        "already exists with different content" in error
        for error in state.validation.errors
    );
}


test "unknown run returns an explicit error state" {
    lookup = get_run(run_id="run-does-not-exist");
    lookup spawn root;
    state = lookup.reports[0];
    assert state.run_state == RunState.IDLE;
    assert not state.validation.valid;
    assert "was not found" in state.validation.errors[0];
}


test "registry exposes exactly the canonical typed seven blocks" {
    catalog = block_catalog();
    assert [definition.block_type for definition in catalog] == [
        "run_now",
        "read_calendar",
        "search_vault",
        "draft_brief",
        "approval",
        "save_brief",
        "open_result"
    ];
    assert all(definition.version == 1 for definition in catalog);
    assert all(definition.config_version == 1 for definition in catalog);
    assert all(definition.handler_version == 1 for definition in catalog);

    workflow = golden_workflow_spec();
    for block in workflow.blocks {
        definition = block_definition(block.block_type);
        assert definition is not None;
        assert block.inputs == [
            port.name for port in definition.input_ports
        ];
        assert block.outputs == [
            port.name for port in definition.output_ports
        ];
        assert block.permissions == definition.permissions;
    }

    assert [
        definition.effect_policy.kind for definition in catalog
    ] == [
        EffectKind.NONE,
        EffectKind.READ,
        EffectKind.READ,
        EffectKind.TRANSFORM,
        EffectKind.APPROVAL,
        EffectKind.WRITE,
        EffectKind.OPEN
    ];
}


test "golden preflight reports bounded effects and blockers" {
    contract = preflight_for_workflow(
        golden_workflow_spec(), "fixture", "run-preflight-test"
    );
    assert contract.state == "ready";
    assert contract.enforcement_level == "experimental";
    assert contract.read_count == 2;
    assert contract.write_count == 1;
    assert contract.send_count == 0;
    assert contract.delete_count == 0;
    assert contract.purchase_count == 0;
    assert contract.maximum_affected_items == 1;
    assert contract.required_approvals == ["save-brief"];
    assert len(contract.resource_scopes) == 4;
    assert all(scope.mode == "fixture" for scope in contract.resource_scopes);
    assert any(
        "Anonymous public walkers" in blocker
        for blocker in contract.blockers
    );
    assert any(
        "Non-fixture exact content is redacted" in blocker
        for blocker in contract.blockers
    );
}


test "registry effect declaration fails closed" {
    assert effect_is_declared(
        "read_calendar", 1, 1, EffectKind.READ
    );
    assert not effect_is_declared(
        "read_calendar", 1, 1, EffectKind.WRITE
    );
    assert not effect_is_declared(
        "read_calendar", 1, 1, EffectKind.NONE
    );
    assert effect_is_declared(
        "save_brief", 1, 1, EffectKind.NONE, "succeeded", "no_change"
    );
    assert effect_is_declared(
        "open_result", 1, 1, EffectKind.NONE, "skipped"
    );
    assert not effect_is_declared(
        "read_calendar", 2, 1, EffectKind.READ
    );
    assert not effect_is_declared(
        "send_email", 1, 1, EffectKind.SEND
    );
}


test "live approval prompt does not expose meeting titles" {
    approval_block = Block(
        block_id="approval",
        block_type="approval",
        title="Approval",
        position=4
    );
    sensitive_title = "Private acquisition discussion";
    context: dict[str, object] = {
        "meetings": [
            CalendarEvent(
                event_id="sensitive-event",
                title=sensitive_title,
                start_at="2026-07-27T09:00:00",
                end_at="2026-07-27T10:00:00"
            )
        ]
    };
    result = execute_registered_block(approval_block, context, "live");
    assert result.outcome == "awaiting_approval";
    assert sensitive_title not in result.approval_prompt;
    assert "redacted live-data proposal" in result.approval_prompt;
}
