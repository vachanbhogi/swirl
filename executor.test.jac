"""Executor result-ordering regression tests."""

import from block_registry { BlockExecutionResult }
import from contracts {
    Block,
    CompilerProvenanceSpec,
    ContainsBlock,
    EffectKind,
    HasRun,
    HasStep,
    ProducedArtifact,
    RequiresApproval,
    Run,
    RunState,
    RunStep,
    StepForBlock,
    StepState,
    ValidationResult,
    Workflow
}
import from graph_store {
    create_run_graph,
    decide_approval,
    materialize_workflow,
    persist_step_output,
    request_approval
}
import from run_contract { execution_result_disposition }
import from workflow { golden_workflow_spec }


def _block(block_type: str) -> Block {
    return Block(
        block_id=block_type,
        block_type=block_type,
        title=block_type,
        position=0,
        block_version=1,
        config_version=1
    );
}


def _step(run: Run, block_id: str) -> RunStep {
    matches = [
        step
        for step in [run->:HasStep:->]
        if step.block_id == block_id
    ];
    assert len(matches) == 1;
    return matches[0];
}


def _new_run -> Run {
    spec = golden_workflow_spec();
    workflow = materialize_workflow(spec, ValidationResult(valid=True));
    return create_run_graph(workflow, spec, "fixture");
}


def _approved_run -> Run {
    run = _new_run();
    first_executor = WorkflowExecutorWalker();
    first_executor spawn run;
    assert run.state == RunState.AWAITING_APPROVAL;
    outcome_state = "";
    for attempt in range(3) {
        approval = [run->:RequiresApproval:->][0];
        outcome = decide_approval(
            run,
            True,
            approval.effect_digest,
            approval.nonce,
            "executor-approval-" + str(approval.generation) + "-" + str(attempt)
        );
        outcome_state = outcome.state;
        if outcome.state == "accepted" {
            break;
        }
    }
    assert outcome_state == "accepted";
    return run;
}


def _legacy_effect_run -> Run {
    workflow = root ++> Workflow(
        workflow_id="legacy-executor-workflow",
        name="Legacy executor workflow",
        version=1,
        revision_digest="",
        compiler_provenance=CompilerProvenanceSpec(
            mode="legacy",
            compiler_id="quaze.parent-format",
            compiler_version="1"
        )
    );
    block = Block(
        block_id="save-brief",
        block_type="save_brief",
        title="Save Brief",
        position=0,
        config={"filename": "Tomorrow Brief.md"}
    );
    workflow +>:ContainsBlock(position=0):+> block;
    run = Run(
        run_id="legacy-executor-run",
        workflow_id=workflow.workflow_id,
        workflow_version=1,
        state=RunState.RUNNING,
        connector_mode="fixture",
        context={"approved_brief": "# Legacy write\n"}
    );
    workflow +>:HasRun:+> run;
    step = RunStep(
        step_id="legacy-effect-step",
        block_id=block.block_id,
        title=block.title,
        position=0,
        block_type=block.block_type,
        block_version=block.block_version,
        config_version=block.config_version,
        state=StepState.PENDING,
        planned_effect=EffectKind.WRITE
    );
    run +>:HasStep(position=0):+> step;
    step +>:StepForBlock:+> block;
    return run;
}


test "connector failures precede successful effect declaration checks" {
    calendar_failure = BlockExecutionResult(
        success=False,
        error="Calendar permission denied.",
        evidence_summary="Calendar connector unavailable."
    );
    assert (
        execution_result_disposition(
            _block("read_calendar"), calendar_failure
        ) == "connector_failure"
    );

    vault_failure = BlockExecutionResult(
        success=False,
        error="Vault unavailable.",
        evidence_summary="Vault connector failed."
    );
    assert (
        execution_result_disposition(
            _block("search_vault"), vault_failure
        ) == "connector_failure"
    );
}


test "target safety failures return to review before effect checks" {
    for error_code in ["target_changed", "unsafe_target"] {
        result = BlockExecutionResult(
            success=False,
            error="Target safety failure.",
            error_code=error_code
        );
        assert (
            execution_result_disposition(_block("save_brief"), result)
            == "target_revalidation"
        );
    }
}


test "successful undeclared effects still fail closed" {
    undeclared_success = BlockExecutionResult(
        success=True,
        outcome="succeeded",
        effect_kind=EffectKind.WRITE
    );
    assert (
        execution_result_disposition(
            _block("read_calendar"), undeclared_success
        ) == "undeclared_effect"
    );
}


test "full executor preserves calendar connector failure ordering" {
    run = _new_run();
    executor = WorkflowExecutorWalker(
        injected_results={
            "read_calendar": BlockExecutionResult(
                success=False,
                error="Injected Calendar permission failure.",
                evidence_summary="Calendar connector failed.",
                effect_kind=EffectKind.WRITE
            )
        }
    );
    executor spawn run;
    calendar = _step(run, "read-calendar");
    assert run.state == RunState.FAILED;
    assert calendar.state == StepState.FAILED;
    assert "Calendar permission failure" in calendar.error;
    assert _step(run, "search-vault").attempt == 0;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "full executor preserves vault connector failure ordering" {
    run = _new_run();
    executor = WorkflowExecutorWalker(
        injected_results={
            "search_vault": BlockExecutionResult(
                success=False,
                error="Injected vault connector failure.",
                evidence_summary="Vault connector failed.",
                effect_kind=EffectKind.WRITE
            )
        }
    );
    executor spawn run;
    vault = _step(run, "search-vault");
    assert _step(run, "read-calendar").state == StepState.SUCCEEDED;
    assert run.state == RunState.FAILED;
    assert vault.state == StepState.FAILED;
    assert "vault connector failure" in vault.error;
    assert _step(run, "draft-brief").attempt == 0;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "full executor returns injected target failure to review before effect persistence" {
    run = _approved_run();
    approved_generation = [run->:RequiresApproval:->][0].generation;
    executor = WorkflowExecutorWalker(
        injected_results={
            "save_brief": BlockExecutionResult(
                success=False,
                error="Injected final target mismatch.",
                error_code="target_changed",
                effect_kind=EffectKind.WRITE
            )
        }
    );
    executor spawn run;
    save_step = _step(run, "save-brief");
    approval = [run->:RequiresApproval:->][0];
    assert run.state == RunState.AWAITING_APPROVAL;
    assert approval.state == "requested";
    assert approval.generation == approved_generation + 1;
    assert save_step.state == StepState.PENDING;
    assert save_step.retry_state == "review_required";
    assert save_step.attempt == 1;
    assert len([run->:ProducedArtifact:->]) == 0;
}


test "legacy and approved live executor entries perform zero effects" {
    legacy = _legacy_effect_run();
    legacy_executor = WorkflowExecutorWalker();
    legacy_executor spawn legacy;
    assert _step(legacy, "save-brief").attempt == 0;
    assert _step(legacy, "save-brief").state == StepState.PENDING;
    assert len([legacy->:ProducedArtifact:->]) == 0;

    live = _approved_run();
    live.connector_mode = "live";
    save_attempt = _step(live, "save-brief").attempt;
    live_executor = WorkflowExecutorWalker(connector_mode="live");
    live_executor spawn live;
    assert live.state == RunState.RUNNING;
    assert _step(live, "save-brief").attempt == save_attempt;
    assert len([live->:ProducedArtifact:->]) == 0;
}
