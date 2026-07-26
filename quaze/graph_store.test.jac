"""Persistent graph lifecycle tests."""

import from contracts {
    CitesEvidence,
    ConnectionSpec,
    HasEvidence,
    ProducedArtifact,
    RunState,
    StepState,
    ValidationResult
}
import from workflow { golden_workflow_spec }

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
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    approval_steps = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ];
    approval = request_approval(run, approval_steps[0], "Review the draft.");
    paused_run_id = run.run_id;
    assert approval.state == "requested";
    assert run.state == RunState.AWAITING_APPROVAL;
    assert decide_approval(run, True);
    assert run.run_id == paused_run_id;
    assert run.state == RunState.RUNNING;
    assert approval_steps[0].state == StepState.SUCCEEDED;
}

test "repeated approval decision is idempotent" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    approval_steps = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ];
    request_approval(run, approval_steps[0], "Review the draft.");
    assert decide_approval(run, True);
    assert not decide_approval(run, True);
    assert len([run->:RequiresApproval:->]) == 1;
}

test "workflow revisions preserve historical run provenance" {
    original = golden_workflow_spec();
    original_node = materialize_workflow(original, ValidationResult(valid=True));
    run = create_run_graph(original_node, original, "fixture");

    revised = golden_workflow_spec();
    revised.version = 2;
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
    assert persisted.workflow.version == 1;
    assert [block.id for block in persisted.workflow.blocks] == [
        block.id for block in original.blocks
    ];
    assert len([run->:HasStep:->]) == 7;
}

test "terminal approval cannot be reopened" {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    run = create_run_graph(workflow, spec, "fixture");
    approval_step = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == "approval"
    ][0];
    approval = request_approval(run, approval_step, "Review the draft.");
    assert decide_approval(run, True);
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
