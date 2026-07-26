"""Registry-dispatched execution for persisted QuaZe runs."""

import from block_registry {
    block_definition,
    execute_registered_block
}
import from contracts {
    Block,
    ExecutionFlow,
    HasStep,
    Run,
    RunState,
    RunStep,
    StepForBlock,
    StepState
}
import from graph_store {
    approved_effect_is_current,
    attach_artifact,
    cancel_persisted_run,
    now_iso,
    persist_step_output,
    rebuild_run_context,
    record_step_event,
    refresh_stale_approval,
    request_approval,
    run_execution_gate_message
}
import from run_contract {
    derive_persisted_receipt,
    execution_result_disposition
}
import from safety { sanitize_public_message }


def _next_step(run: Run, step: RunStep) -> RunStep | None {
    blocks = [step->:StepForBlock:->];
    if not blocks {
        return None;
    }
    next_blocks = [blocks[0]->:ExecutionFlow:->];
    if not next_blocks {
        return None;
    }
    next_block_id = next_blocks[0].block_id;
    for candidate in [run->:HasStep:->] {
        if candidate.block_id == next_block_id {
            return candidate;
        }
    }
    return None;
}


def _block_for_step(step: RunStep) -> Block | None {
    blocks = [step->:StepForBlock:->];
    return blocks[0] if blocks else None;
}


def _context_strings(run: Run, key: str) -> list[str] {
    value = run.context.get(key);
    return value as list[str] if isinstance(value, list) else [];
}


def _begin_step(run: Run, step: RunStep) {
    step.state = StepState.RUNNING;
    step.attempt += 1;
    step.retry_state = "running";
    step.started_at = now_iso();
    step.completed_at = "";
    step.error = "";
    record_step_event(run, step, "step_started", f"{step.title} started.");
}


def _succeed_step(run: Run, step: RunStep, evidence_summary: str) {
    evidence_summary = sanitize_public_message(evidence_summary, "");
    step.state = StepState.SUCCEEDED;
    step.retry_state = "complete";
    step.completed_at = now_iso();
    step.evidence_summary = evidence_summary;
    record_step_event(run, step, "step_succeeded", evidence_summary);
}


def _skip_step(run: Run, step: RunStep, evidence_summary: str) {
    evidence_summary = sanitize_public_message(evidence_summary, "");
    step.state = StepState.SKIPPED;
    step.retry_state = "complete";
    step.completed_at = now_iso();
    step.evidence_summary = evidence_summary;
    record_step_event(run, step, "step_skipped", evidence_summary);
}


def _fail_step(run: Run, step: RunStep, error: str, evidence_summary: str = "") {
    error = sanitize_public_message(error);
    evidence_summary = sanitize_public_message(evidence_summary, "");
    step.state = StepState.FAILED;
    definition = block_definition(step.block_type);
    step.retry_state = (
        "available"
            if (
                definition is not None
                and definition.retry_policy.idempotent
                and step.attempt < definition.retry_policy.max_attempts
            )
            else "exhausted"
    );
    step.completed_at = now_iso();
    step.error = error;
    step.evidence_summary = evidence_summary;
    run.state = RunState.FAILED;
    record_step_event(
        run,
        step,
        "step_failed",
        evidence_summary + (" " if evidence_summary else "") + error
    );
    derive_persisted_receipt(run);
}


def _finish_if_terminal(run: Run, step: RunStep) {
    next_step = _next_step(run, step);
    if next_step is None and run.state == RunState.RUNNING {
        run.state = RunState.SUCCEEDED;
        run.updated_at = now_iso();
        derive_persisted_receipt(run);
    }
}

walker WorkflowExecutorWalker {
    has connector_mode: str = "fixture",
        injected_results: dict[str, BlockExecutionResult] = {};

    can begin with Run entry {
        self.connector_mode = here.connector_mode;
        if run_execution_gate_message(here) {
            disengage;
        }
        if here.cancel_requested {
            cancel_persisted_run(here);
            disengage;
        }
        if here.state in [
            RunState.AWAITING_APPROVAL,
            RunState.SUCCEEDED,
            RunState.FAILED,
            RunState.CANCELED
        ] {
            disengage;
        }
        rebuild_run_context(here);
        steps = [here->:HasStep:->];
        steps.sort(key=lambda (step: RunStep) { step.position; });
        if not steps {
            here.state = RunState.FAILED;
            here.updated_at = now_iso();
            derive_persisted_receipt(here);
            disengage;
        }
        visit steps[0];
    }

    can execute_step with RunStep entry {
        runs = [here<-:HasStep:<-];
        if not runs {
            disengage;
        }
        run: Run = runs[0];
        if run_execution_gate_message(run) {
            disengage;
        }
        if run.cancel_requested {
            cancel_persisted_run(run);
            disengage;
        }
        if here.state in [StepState.SUCCEEDED, StepState.SKIPPED] {
            next_completed_step = _next_step(run, here);
            if next_completed_step is not None {
                visit next_completed_step;
            } else {
                _finish_if_terminal(run, here);
            }
            return;
        }
        if run.state != RunState.RUNNING {
            disengage;
        }

        candidate_block = _block_for_step(here);
        if candidate_block is None {
            _begin_step(run, here);
            _fail_step(run, here, "The persisted step is detached from its block.");
            disengage;
        }
        block: Block = candidate_block;
        definition = block_definition(block.block_type);
        if (
            definition is None
            or block.block_version != definition.version
            or block.config_version != definition.config_version
            or here.block_type != block.block_type
            or here.block_version != block.block_version
            or here.config_version != block.config_version
        ) {
            _begin_step(run, here);
            _fail_step(run, here, "The persisted block contract is unsupported.");
            disengage;
        }

        injected_result = self.injected_results.get(block.block_type);
        injected_failure: BlockExecutionResult | None = (
            injected_result
                if (
                    isinstance(injected_result, BlockExecutionResult)
                    and not injected_result.success
                )
                else None
        );
        injected_target_revalidation = (
            injected_failure is not None
            and injected_failure.error_code in ["target_changed", "unsafe_target"]
        );
        if definition.effect_policy.requires_approval {
            if (
                not injected_target_revalidation
                and not approved_effect_is_current(run)
            ) {
                here.state = StepState.PENDING;
                here.retry_state = "review_required";
                disengage;
            }
            run.context["expected_prior_hash"] = (
                run.effect_proposal.prior_target_hash
            );
            here.effect_digest = run.effect_proposal.effect_digest;
        }

        _begin_step(run, here);
        result: BlockExecutionResult = (
            injected_failure
                if injected_failure is not None
                else execute_registered_block(
                    block, run.context, self.connector_mode
                )
        );
        result_disposition = execution_result_disposition(block, result);
        if result_disposition == "target_revalidation" {
            here.state = StepState.PENDING;
            here.retry_state = "review_required";
            here.completed_at = "";
            here.error = "";
            refresh_stale_approval(
                run,
                (
                    "The write target was rejected by the safety boundary."
                        if result.error_code == "unsafe_target"
                        else "The target changed at the final write precondition."
                )
            );
            disengage;
        }
        if result_disposition == "connector_failure" {
            _fail_step(run, here, result.error, result.evidence_summary);
            disengage;
        }
        if result_disposition == "undeclared_effect" {
            _fail_step(run, here, "The runtime attempted an undeclared effect.");
            disengage;
        }
        if result.outcome == "awaiting_approval" {
            request_approval(run, here, result.approval_prompt);
            disengage;
        }

        if result.artifact_path {
            # Persist the artifact/effect outcome before the step output or
            # terminal success so recovery never infers a write from a step alone.
            attach_artifact(
                run,
                result.artifact_path,
                result.artifact_hash,
                _context_strings(run, "source_references"),
                run.effect_proposal.effect_digest,
                result.write_state
            );
        }
        # Persist exact step output and evidence before the step can become
        # terminal or the walker can advance.
        persist_step_output(
            run,
            here,
            result.context_updates,
            result.evidence_snapshot_hashes,
            result.effect_kind
        );
        if result.outcome == "skipped" {
            _skip_step(run, here, result.evidence_summary);
        } else {
            _succeed_step(run, here, result.evidence_summary);
        }

        next_step = _next_step(run, here);
        if next_step is not None {
            visit next_step;
        } else {
            _finish_if_terminal(run, here);
        }
    }
}
