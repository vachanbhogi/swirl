"""Public lifecycle walkers for QuaZe prompt-generated workflows."""

import from contracts { DemoState, RunState, ValidationResult, WorkflowSpec }
import from block_registry { block_catalog }
import from compiler { compile_prompt_state }
import from executor { WorkflowExecutorWalker }
import from graph_store {
    cancel_persisted_run,
    create_run_graph,
    decide_approval,
    find_run,
    materialize_workflow,
    prepare_failed_run_retry,
    recover_persisted_run,
    run_to_demo_state
}
import from runtime { reorder_workflow_spec, validate_workflow_spec }
import from run_contract { preflight_for_workflow }
import from workflow { initial_demo_state }


def _state_for_workflow(
    workflow: WorkflowSpec, validation: ValidationResult, notice: str
) -> DemoState {
    workflow.validation = validation;
    return DemoState(
        workflow=workflow,
        validation=validation,
        block_catalog=block_catalog(),
        run_contract=preflight_for_workflow(workflow),
        compiler_provenance=workflow.compiler_provenance,
        compiler_mode=workflow.compiler_provenance.mode,
        compiler_notice=notice
    );
}


def _error_state(message: str) -> DemoState {
    state = initial_demo_state(compiler_mode="error", compiler_notice=message);
    state.validation = ValidationResult(valid=False, errors=[message]);
    state.workflow.validation = state.validation;
    return state;
}


def _block_order(workflow: WorkflowSpec) -> list[str] {
    return [block.id for block in workflow.blocks];
}


walker:pub compile_prompt {
    has prompt: str,
        reports: list[DemoState] = [];

    can compile with Root entry {
        state = compile_prompt_state(self.prompt);
        validation = validate_workflow_spec(state.workflow);
        state.workflow.validation = validation;
        state.validation = validation;
        try {
            materialize_workflow(state.workflow, validation);
        } except ValueError as error {
            validation.valid = False;
            validation.errors.append(str(error));
            state.workflow.validation = validation;
            state.validation = validation;
            state.compiler_notice = "Workflow revision materialization was rejected.";
        }
        report state;
    }
}


walker:pub validate_workflow {
    has workflow: WorkflowSpec,
        reports: list[DemoState] = [];

    can validate with Root entry {
        validation = validate_workflow_spec(self.workflow);
        self.workflow.validation = validation;
        try {
            materialize_workflow(self.workflow, validation);
        } except ValueError as error {
            validation.valid = False;
            validation.errors.append(str(error));
        }
        report _state_for_workflow(
            self.workflow,
            validation,
            (
                "Workflow validation passed."
                    if validation.valid
                    else "Workflow validation failed. Review the listed findings."
            )
        );
    }
}


walker:pub reorder_blocks {
    has workflow: WorkflowSpec,
        block_id: str,
        direction: str,
        reports: list[DemoState] = [];

    can reorder with Root entry {
        original_order = _block_order(self.workflow);
        reordered = reorder_workflow_spec(self.workflow, self.block_id, self.direction);
        if _block_order(reordered) != original_order {
            reordered.version = self.workflow.version + 1;
        }
        try {
            materialize_workflow(reordered, reordered.validation);
        } except ValueError as error {
            reordered.validation.valid = False;
            reordered.validation.errors.append(str(error));
        }
        report _state_for_workflow(
            reordered,
            reordered.validation,
            (
                "Block order updated and validated."
                    if reordered.validation.valid
                    else "Block order updated; validation found unsafe data flow."
            )
        );
    }
}


walker:pub start_run {
    has workflow: WorkflowSpec,
        connector_mode: str = "fixture",
        reports: list[DemoState] = [];

    can start with Root entry {
        validation = validate_workflow_spec(self.workflow);
        self.workflow.validation = validation;
        if self.connector_mode != "fixture" {
            state = _state_for_workflow(
                self.workflow,
                validation,
                "Live execution is unavailable in this experimental checkpoint."
            );
            state.run_contract.state = "unavailable";
            state.run_contract.connector_mode = "fixture";
            state.run_contract.blockers.append(
                "Live execution is unavailable until owner-scoped private review is implemented."
            );
            report state;
            return;
        }
        if self.workflow.version < 2 {
            validation.valid = False;
            validation.errors.append(
                "Legacy workflow version 1 is read-only and cannot start a run."
            );
        }
        if not validation.valid {
            report _state_for_workflow(
                self.workflow,
                validation,
                "Run stopped before execution because validation failed."
            );
            return;
        }

        try {
            workflow_node = materialize_workflow(self.workflow, validation);
        } except ValueError as error {
            validation.valid = False;
            validation.errors.append(str(error));
            report _state_for_workflow(
                self.workflow,
                validation,
                "Run stopped because the workflow revision was rejected."
            );
            return;
        }
        run = create_run_graph(workflow_node, self.workflow, self.connector_mode);
        executor = WorkflowExecutorWalker(connector_mode=self.connector_mode);
        executor spawn run;
        report run_to_demo_state(run);
    }
}


walker:pub approve_run {
    has run_id: str,
        approved: bool,
        effect_digest: str,
        approval_nonce: str,
        decision_request_id: str,
        reports: list[DemoState] = [];

    can approve with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }

        outcome = decide_approval(
            run,
            self.approved,
            self.effect_digest,
            self.approval_nonce,
            self.decision_request_id
        );
        state = run_to_demo_state(run);
        state.approval_outcome = outcome;
        report state;
    }
}


walker:pub cancel_run {
    has run_id: str,
        reports: list[DemoState] = [];

    can cancel with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }
        cancel_persisted_run(run);
        report run_to_demo_state(run);
    }
}


walker:pub recover_run {
    has run_id: str,
        reports: list[DemoState] = [];

    can recover with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }
        recovered = recover_persisted_run(run);
        if recovered and run.state == RunState.RUNNING {
            executor = WorkflowExecutorWalker(connector_mode=run.connector_mode);
            executor spawn run;
        }
        report run_to_demo_state(run);
    }
}


walker:pub retry_run {
    has run_id: str,
        reports: list[DemoState] = [];

    can retry with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }
        if prepare_failed_run_retry(run) {
            executor = WorkflowExecutorWalker(connector_mode=run.connector_mode);
            executor spawn run;
        }
        report run_to_demo_state(run);
    }
}


walker:pub get_run {
    has run_id: str,
        reports: list[DemoState] = [];

    can get with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }
        report run_to_demo_state(run);
    }
}
