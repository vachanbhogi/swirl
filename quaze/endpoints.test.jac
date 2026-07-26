"""Public walker integration and persisted-run lifecycle tests."""

import os;
import from contracts { ConnectorResult, DemoState, RunState, RunStepSpec, StepState }
import from connectors { BRIEF_FILENAME, resolve_demo_vault_path }
import from workflow { golden_workflow_spec }


def _result_string(result: ConnectorResult, key: str) -> str {
    value = result.data.get(key);
    return value if isinstance(value, str) else "";
}


def _brief_path -> str {
    resolved = resolve_demo_vault_path(BRIEF_FILENAME);
    assert resolved.success , resolved.error;
    return _result_string(resolved, "path");
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

    reordered = reorder_blocks(
        workflow=compiled_state.workflow, block_id="approval", direction="down"
    );
    reordered spawn root;
    reordered_state = reordered.reports[0];
    assert not reordered_state.validation.valid;
    assert (
        "Save Brief must be immediately preceded by Approval." in reordered_state.validation.errors
    );
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
        paused_run_id = paused.run_id;

        loaded = get_run(run_id=paused_run_id);
        loaded spawn root;
        assert loaded.reports[0].run_id == paused_run_id;
        assert loaded.reports[0].run_state == RunState.AWAITING_APPROVAL;

        approved = approve_run(run_id=paused_run_id, approved=True);
        approved spawn root;
        completed = approved.reports[0];
        assert completed.run_id == paused_run_id;
        assert completed.run_state == RunState.SUCCEEDED;
        assert _step(completed, "save-brief").state == StepState.SUCCEEDED;
        assert _step(completed, "save-brief").attempt == 1;
        assert _step(completed, "open-result").state == StepState.SKIPPED;
        assert completed.artifact.path.endswith(
            "/fixtures/demo-vault/Tomorrow Brief.md"
        );
        assert completed.artifact.content_hash != "";
        assert len(completed.artifact.source_references) == 4;
        event_count = len(completed.events);
        artifact_id = completed.artifact.id;

        repeated = approve_run(run_id=paused_run_id, approved=True);
        repeated spawn root;
        repeated_state = repeated.reports[0];
        assert repeated_state.run_id == paused_run_id;
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

    rejected = approve_run(run_id=paused.run_id, approved=False);
    rejected spawn root;
    stopped = rejected.reports[0];
    assert stopped.run_id == paused.run_id;
    assert stopped.run_state == RunState.FAILED;
    assert stopped.approval.state == "rejected";
    assert _step(stopped, "save-brief").state == StepState.PENDING;
    assert stopped.artifact.path == "";
}


test "unknown run returns an explicit error state" {
    lookup = get_run(run_id="run-does-not-exist");
    lookup spawn root;
    state = lookup.reports[0];
    assert state.run_state == RunState.IDLE;
    assert not state.validation.valid;
    assert "was not found" in state.validation.errors[0];
}
