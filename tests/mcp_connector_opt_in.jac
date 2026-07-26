"""Opt-in installed MCP check; run directly, never through the default suite."""

import from connectors {
    events_from_result,
    notes_from_result,
    read_fixture_calendar,
    search_vault
}


with entry:__main__ {
    calendar_result = read_fixture_calendar("2026-07-26");
    assert calendar_result.success , calendar_result.error;
    mcp_result = search_vault(
        events_from_result(calendar_result), connector_mode="mcp", allow_fallback=False
    );
    assert mcp_result.success , mcp_result.error;
    assert mcp_result.evidence_summary.startswith("mcp official-filesystem-stdio:");
    note_paths = [note.path for note in notes_from_result(mcp_result)];
    assert len(note_paths) == 2;
    assert "Apex Project.md" in note_paths;
    assert "Maya People.md" in note_paths;
    assert "Weekend Errands.md" not in note_paths;
    print(mcp_result.evidence_summary);
}
