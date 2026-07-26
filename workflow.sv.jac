"""QuaZe's first supported workflow template: tomorrow's meeting brief."""

import from contracts {
    BlockSpec,
    CompilerProvenanceSpec,
    ConnectionSpec,
    DemoState,
    ValidationResult,
    WorkflowSpec
}
import from block_registry { block_catalog, build_block_spec }
import from run_contract { preflight_for_workflow }


def _golden_block(block_type: str, block_id: str) -> BlockSpec {
    block = build_block_spec(block_type, block_id);
    if block is None {
        raise ValueError(f"Missing canonical block definition: {block_type}.");
    }
    return block;
}

def golden_workflow_spec -> WorkflowSpec {
    blocks = [
        _golden_block("run_now", "run-now"),
        _golden_block("read_calendar", "read-calendar"),
        _golden_block("search_vault", "search-vault"),
        _golden_block("draft_brief", "draft-brief"),
        _golden_block("approval", "approval"),
        _golden_block("save_brief", "save-brief"),
        _golden_block("open_result", "open-result")
    ];
    connections = [
        ConnectionSpec(
            source_id="run-now",
            target_id="read-calendar",
            source_port="run_request",
            target_port="run_request"
        ),
        ConnectionSpec(
            source_id="read-calendar",
            target_id="search-vault",
            source_port="meetings",
            target_port="meetings"
        ),
        ConnectionSpec(
            source_id="search-vault",
            target_id="draft-brief",
            source_port="matched_notes",
            target_port="matched_notes"
        ),
        ConnectionSpec(
            source_id="draft-brief",
            target_id="approval",
            source_port="brief_markdown",
            target_port="brief_markdown"
        ),
        ConnectionSpec(
            source_id="approval",
            target_id="save-brief",
            source_port="approved_brief",
            target_port="approved_brief"
        ),
        ConnectionSpec(
            source_id="save-brief",
            target_id="open-result",
            source_port="artifact",
            target_port="artifact"
        )
    ];
    validation = ValidationResult(valid=True);
    return WorkflowSpec(
        id="tomorrow-meeting-brief",
        name="Tomorrow meeting brief",
        version=2,
        blocks=blocks,
        connections=connections,
        validation=validation
    );
}

def initial_demo_state(
    compiler_mode: str = "deterministic",
    compiler_notice: str = "",
    compiler_provenance: CompilerProvenanceSpec = CompilerProvenanceSpec()
) -> DemoState {
    workflow = golden_workflow_spec();
    workflow.compiler_provenance = compiler_provenance;
    return DemoState(
        workflow=workflow,
        validation=workflow.validation,
        block_catalog=block_catalog(),
        run_contract=preflight_for_workflow(workflow),
        compiler_provenance=compiler_provenance,
        compiler_mode=compiler_mode,
        compiler_notice=compiler_notice
    );
}
