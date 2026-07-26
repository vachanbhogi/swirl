"""Public lifecycle walkers for QuaZe prompt-generated workflows."""

import from contracts { DemoState, ValidationResult, WorkflowSpec }
import from compiler { compile_prompt_state }
import from executor { WorkflowExecutorWalker }
import from graph_store {
    create_run_graph,
    decide_approval,
    find_run,
    materialize_workflow,
    run_to_demo_state
}
import from runtime { reorder_workflow_spec, validate_workflow_spec }
import from workflow { initial_demo_state }


def _state_for_workflow(
    workflow: WorkflowSpec, validation: ValidationResult, mode: str, notice: str
) -> DemoState {
    workflow.validation = validation;
    return DemoState(
        workflow=workflow,
        validation=validation,
        compiler_mode=mode,
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
        materialize_workflow(state.workflow, validation);
        report state;
    }
}


walker:pub validate_workflow {
    has workflow: WorkflowSpec,
        reports: list[DemoState] = [];

    can validate with Root entry {
        validation = validate_workflow_spec(self.workflow);
        self.workflow.validation = validation;
        materialize_workflow(self.workflow, validation);
        report _state_for_workflow(
            self.workflow,
            validation,
            "validated",
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
        materialize_workflow(reordered, reordered.validation);
        report _state_for_workflow(
            reordered,
            reordered.validation,
            "validated",
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
        if self.connector_mode not in ["fixture", "live"] {
            validation.valid = False;
            validation.errors.append("Connector mode must be fixture or live.");
        }
        self.workflow.validation = validation;
        if not validation.valid {
            report _state_for_workflow(
                self.workflow,
                validation,
                "validated",
                "Run stopped before execution because validation failed."
            );
            return;
        }

        workflow_node = materialize_workflow(self.workflow, validation);
        run = create_run_graph(workflow_node, self.workflow, self.connector_mode);
        executor = WorkflowExecutorWalker(connector_mode=self.connector_mode);
        executor spawn run;
        report run_to_demo_state(run);
    }
}


walker:pub approve_run {
    has run_id: str,
        approved: bool,
        reports: list[DemoState] = [];

    can approve with Root entry {
        run = find_run(self.run_id);
        if run is None {
            report _error_state(f"Persisted run {self.run_id} was not found.");
            return;
        }

        decision_recorded = decide_approval(run, self.approved);
        if decision_recorded and self.approved {
            connector_mode_value = run.context.get("connector_mode");
            connector_mode = (
                connector_mode_value
                    if isinstance(connector_mode_value, str)
                    else "fixture"
            );
            executor = WorkflowExecutorWalker(connector_mode=connector_mode);
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
