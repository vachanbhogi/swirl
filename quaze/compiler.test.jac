"""Deterministic prompt compiler tests."""

import from contracts { DemoState }

test "golden prompt produces the seven supported blocks" {
    state: DemoState = compile_prompt_for_mode(
        "Prepare me for tomorrow's meetings and ask before saving.", False
    );
    block_types = [block.block_type for block in state.workflow.blocks];
    assert block_types == canonical_block_types();
    assert state.compiler_mode == "deterministic";
    assert "meeting-prep workflow" in state.compiler_notice;
}

test "unsupported intent activates labeled deterministic mode" {
    state: DemoState = compile_prompt_for_mode(
        "Send an email and delete every file on my Desktop.", False
    );
    block_types = [block.block_type for block in state.workflow.blocks];
    assert block_types == canonical_block_types();
    assert state.compiler_mode == "deterministic_fallback";
    assert "unsupported" in state.compiler_notice;
    assert "meeting-prep workflow" in state.compiler_notice;
}

test "empty hosted prompt falls back without a model call" {
    state: DemoState = compile_prompt_for_mode("  ", True);
    assert state.compiler_mode == "deterministic_fallback";
    assert len(state.workflow.blocks) == 7;
}
