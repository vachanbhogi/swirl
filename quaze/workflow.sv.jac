"""QuaZe's first supported workflow template: tomorrow's meeting brief."""

import from contracts {
    BlockSpec,
    ConnectionSpec,
    DemoState,
    ValidationResult,
    WorkflowSpec
}

def golden_workflow_spec -> WorkflowSpec {
    blocks = [
        BlockSpec(
            id="run-now", block_type="run_now", title="Run Now", outputs=["run_request"]
        ),
        BlockSpec(
            id="read-calendar",
            block_type="read_calendar",
            title="Read Calendar",
            config={"calendar": "QuaZe Demo", "range": "tomorrow"},
            inputs=["run_request"],
            outputs=["meetings"],
            permissions=["calendar.read"]
        ),
        BlockSpec(
            id="search-vault",
            block_type="search_vault",
            title="Search Vault",
            config={"vault": "fixtures/demo-vault"},
            inputs=["meetings"],
            outputs=["matched_notes"],
            permissions=["vault.read"]
        ),
        BlockSpec(
            id="draft-brief",
            block_type="draft_brief",
            title="Draft Brief",
            inputs=["meetings", "matched_notes"],
            outputs=["brief_markdown"]
        ),
        BlockSpec(
            id="approval",
            block_type="approval",
            title="Approval",
            inputs=["brief_markdown"],
            outputs=["approved_brief"],
            permissions=["human.approval"]
        ),
        BlockSpec(
            id="save-brief",
            block_type="save_brief",
            title="Save Brief",
            config={"filename": "Tomorrow Brief.md"},
            inputs=["approved_brief"],
            outputs=["artifact"],
            permissions=["vault.write"]
        ),
        BlockSpec(
            id="open-result",
            block_type="open_result",
            title="Open Result",
            inputs=["artifact"],
            outputs=["opened_artifact"],
            permissions=["obsidian.open"]
        )
    ];
    connections = [
        ConnectionSpec(source_id="run-now", target_id="read-calendar"),
        ConnectionSpec(source_id="read-calendar", target_id="search-vault"),
        ConnectionSpec(source_id="search-vault", target_id="draft-brief"),
        ConnectionSpec(source_id="draft-brief", target_id="approval"),
        ConnectionSpec(source_id="approval", target_id="save-brief"),
        ConnectionSpec(source_id="save-brief", target_id="open-result")
    ];
    validation = ValidationResult(valid=True);
    return WorkflowSpec(
        id="tomorrow-meeting-brief",
        name="Tomorrow meeting brief",
        version=1,
        blocks=blocks,
        connections=connections,
        validation=validation
    );
}

def initial_demo_state(
    compiler_mode: str = "deterministic", compiler_notice: str = ""
) -> DemoState {
    workflow = golden_workflow_spec();
    return DemoState(
        workflow=workflow,
        validation=workflow.validation,
        compiler_mode=compiler_mode,
        compiler_notice=compiler_notice
    );
}
