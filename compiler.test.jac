"""Deterministic prompt compiler tests."""

import from contracts { DemoState }

test "golden prompt produces the seven supported blocks" {
    state: DemoState = compile_prompt_for_mode(
        "Prepare me for tomorrow's meetings and ask before saving.", False
    );
    block_types = [block.block_type for block in state.workflow.blocks];
    assert block_types == canonical_block_types();
    assert state.compiler_mode == "deterministic";
    assert state.compiler_provenance.mode == "deterministic";
    assert state.compiler_provenance.compiler_id == "quaze.golden-workflow";
    assert state.compiler_provenance.compiler_version == "2";
    assert state.workflow.version == 2;
    assert "meeting-prep workflow" in state.compiler_notice;
}

test "unsupported intent activates labeled deterministic mode" {
    state: DemoState = compile_prompt_for_mode(
        "Send an email and delete every file on my Desktop.", False
    );
    block_types = [block.block_type for block in state.workflow.blocks];
    assert block_types == canonical_block_types();
    assert state.compiler_mode == "deterministic_fallback";
    assert state.compiler_provenance.mode == "deterministic_fallback";
    assert state.compiler_provenance.fallback_reason == "unsupported_intent";
    assert "unsupported" in state.compiler_notice;
    assert "meeting-prep workflow" in state.compiler_notice;
}

test "empty hosted prompt falls back without a model call" {
    state: DemoState = compile_prompt_for_mode("  ", True);
    assert state.compiler_mode == "deterministic_fallback";
    assert state.compiler_provenance.fallback_reason == "empty_prompt";
    assert state.compiler_provenance.outbound_data == [];
    assert len(state.workflow.blocks) == 7;
}

test "typed hosted provenance discloses outbound data without prompt content" {
    provenance = _provenance(
        "hosted",
        "jac.byllm",
        outbound_data=[
            "Prompt text was sent to the configured hosted compiler."
        ]
    );
    assert provenance.mode == "hosted";
    assert provenance.compiler_version == "2";
    assert len(provenance.outbound_data) == 1;
    assert "Prepare tomorrow" not in str(provenance);
}
