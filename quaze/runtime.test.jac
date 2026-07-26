"""Deterministic runtime and connector acceptance scenarios."""

import from contracts { ConnectionSpec, ConnectorResult }
import from workflow { golden_workflow_spec }
import from connectors {
    BRIEF_FILENAME,
    decode_live_calendar_output,
    draft_brief,
    events_from_result,
    notes_from_result,
    read_fixture_calendar,
    resolve_demo_vault_path,
    save_brief,
    search_vault
}

def _result_string(result: ConnectorResult, key: str) -> str {
    value = result.data.get(key);
    if isinstance(value, str) {
        return value;
    }
    return "";
}


def _fixture_calendar -> ConnectorResult {
    return read_fixture_calendar("2026-07-26");
}


def _fixture_vault(calendar_result: ConnectorResult) -> ConnectorResult {
    return search_vault(events_from_result(calendar_result), connector_mode="fixture");
}


test "golden workflow validates" {
    validation = validate_workflow_spec(golden_workflow_spec());
    assert validation.valid , str(validation.errors);
    assert len(validation.errors) == 0;
}


test "unsupported block rejects" {
    workflow = golden_workflow_spec();
    workflow.blocks[1].block_type = "send_email";
    validation = validate_workflow_spec(workflow);
    assert not validation.valid;
    assert "Unsupported block type: send_email." in validation.errors;
}


test "missing stable and duplicate IDs reject" {
    missing_workflow = golden_workflow_spec();
    missing_workflow.blocks[1].id = " ";
    missing_validation = validate_workflow_spec(missing_workflow);
    assert not missing_validation.valid;
    assert (
        "Every block must have a non-empty stable ID." in missing_validation.errors
    );

    duplicate_workflow = golden_workflow_spec();
    duplicate_workflow.blocks[1].id = duplicate_workflow.blocks[0].id;
    duplicate_validation = validate_workflow_spec(duplicate_workflow);
    assert not duplicate_validation.valid;
    assert ("Duplicate stable block ID: run-now." in duplicate_validation.errors);
}


test "missing connection endpoint rejects" {
    workflow = golden_workflow_spec();
    workflow.connections[0].target_id = "missing-block";
    validation = validate_workflow_spec(workflow);
    assert not validation.valid;
    assert ("Connection target does not exist: missing-block." in validation.errors);
}


test "missing input rejects" {
    workflow = golden_workflow_spec();
    workflow.blocks[3].inputs = ["meetings"];
    validation = validate_workflow_spec(workflow);
    assert not validation.valid;
    assert (
        "Block draft-brief is missing required input matched_notes." in validation.errors
    );
}


test "cycle rejects" {
    workflow = golden_workflow_spec();
    workflow.connections.append(
        ConnectionSpec(source_id="open-result", target_id="read-calendar")
    );
    validation = validate_workflow_spec(workflow);
    assert not validation.valid;
    assert "Workflow contains a cycle." in validation.errors;
}


test "unreachable step rejects" {
    workflow = golden_workflow_spec();
    workflow.connections = [
        connection
        for connection in workflow.connections
        if connection.source_id != "read-calendar"
    ];
    validation = validate_workflow_spec(workflow);
    assert not validation.valid;
    assert `any(
        error.startswith("Unreachable workflow steps:") for error in validation.errors
    );
}


test "unavailable connector rejects" {
    validation = validate_workflow_spec(
        golden_workflow_spec(), ["vault", "filesystem", "obsidian"]
    );
    assert not validation.valid;
    assert (
        "Connector calendar required by block read-calendar is unavailable." in validation.errors
    );
}


test "moving Approval away from Save Brief rejects" {
    reordered = reorder_workflow_spec(golden_workflow_spec(), "approval", "down");
    assert not reordered.validation.valid;
    assert (
        "Save Brief must be immediately preceded by Approval." in reordered.validation.errors
    );
}

test "moving a consumer before its producer rejects" {
    reordered = reorder_workflow_spec(golden_workflow_spec(), "search-vault", "down");
    assert not reordered.validation.valid;
    assert (
        "Block draft-brief input matched_notes is unavailable before execution." in reordered.validation.errors
    );
}


test "boundary reorder is idempotent" {
    reordered = reorder_workflow_spec(golden_workflow_spec(), "run-now", "up");
    assert reordered.blocks[0].id == "run-now";
    assert reordered.validation.valid , str(reordered.validation.errors);
}


test "connector failure stops before artifact" {
    failed_calendar = ConnectorResult(
        success=False,
        evidence_summary="fixture: injected Calendar failure.",
        error="Calendar fixture failed."
    );
    result = prepare_run(
        golden_workflow_spec(), failed_calendar, ConnectorResult(success=True)
    );
    assert not result.success;
    assert result.state == "failed";
    assert not result.save_called;
    assert result.artifact_path == "";
    assert result.artifact_hash == "";
}


test "pre approval produces draft without save" {
    calendar_result = _fixture_calendar();
    vault_result = _fixture_vault(calendar_result);
    prepared = prepare_run(golden_workflow_spec(), calendar_result, vault_result);
    assert prepared.success , prepared.error;
    assert prepared.state == "awaiting_approval";
    assert prepared.draft_markdown.startswith("# Tomorrow Brief");
    assert not prepared.save_called;
    assert prepared.artifact_path == "";
    assert prepared.artifact_hash == "";
}


test "fixture search includes Apex and Maya notes" {
    calendar_result = _fixture_calendar();
    search_result = _fixture_vault(calendar_result);
    assert search_result.success , search_result.error;
    notes = notes_from_result(search_result);
    note_paths = [note.path for note in notes];
    assert "Apex Project.md" in note_paths;
    assert "Maya People.md" in note_paths;
    apex_note = [note for note in notes if note.path == "Apex Project.md"][0];
    maya_note = [note for note in notes if note.path == "Maya People.md"][0];
    assert apex_note.meeting_ids == ["apex-design-review"];
    assert maya_note.meeting_ids == ["maya-onboarding"];
}


test "fixture search excludes irrelevant note" {
    calendar_result = _fixture_calendar();
    search_result = _fixture_vault(calendar_result);
    note_paths = [note.path for note in notes_from_result(search_result)];
    assert "Weekend Errands.md" not in note_paths;
    assert BRIEF_FILENAME not in note_paths;
}


test "live Calendar parser preserves empty attendees" {
    field_separator = chr(31);
    raw_output = field_separator.join(
        [
            "empty-attendees",
            "No attendee demo",
            "Monday, July 27, 2026 at 9:00:00 AM",
            "Monday, July 27, 2026 at 9:30:00 AM",
            ""
        ]
    ) + "\n";
    parsed = decode_live_calendar_output(raw_output);
    assert parsed.success , parsed.error;
    events = events_from_result(parsed);
    assert len(events) == 1;
    assert events[0].event_id == "empty-attendees";
    assert len(events[0].attendees) == 0;
}


test "draft cites sources and marks missing context" {
    calendar_result = _fixture_calendar();
    vault_result = _fixture_vault(calendar_result);
    draft_result = draft_brief(
        events_from_result(calendar_result), notes_from_result(vault_result)
    );
    assert draft_result.success , draft_result.error;
    markdown = _result_string(draft_result, "markdown");
    assert "fixture-calendar://apex-design-review" in markdown;
    assert "fixture-calendar://maya-onboarding" in markdown;
    assert "vault://Apex%20Project.md" in markdown;
    assert "vault://Maya%20People.md" in markdown;
    assert "Missing context:" in markdown;
    assert "Weekend Errands" not in markdown;
}


test "path traversal is rejected" {
    resolved = resolve_demo_vault_path("../AGENTS.md");
    assert not resolved.success;
    assert "escapes the dedicated demo vault" in resolved.error;

    saved = save_brief("approved", [], "../escape.md");
    assert not saved.success;
    assert "Tomorrow Brief.md" in saved.error;
}
