"""Bounded Calendar, vault, drafting, artifact, and open-result connectors."""

import re;
import connector_host;
import from contracts { ConnectorResult }


glob DEMO_CALENDAR: str = "QuaZe Demo";
glob DEMO_VAULT: str = "fixtures/demo-vault";
glob BRIEF_FILENAME: str = "Tomorrow Brief.md";
glob MATCH_STOPWORDS: set[str] = {
         "and",
         "for",
         "from",
         "into",
         "meeting",
         "review",
         "the",
         "this",
         "tomorrow",
         "with"
     };


obj CalendarEvent {
    has event_id: str,
        title: str,
        start_at: str,
        end_at: str,
        attendees: list[str] = [],
        source_ref: str = "";
}


obj VaultNote {
    has path: str,
        title: str,
        content: str,
        meeting_ids: list[str] = [],
        source_ref: str = "";
}


def _string_value(data: dict[str, object], key: str) -> str {
    value = data.get(key);
    if isinstance(value, str) {
        return value;
    }
    return "";
}


def _bool_value(data: dict[str, object], key: str) -> bool {
    value = data.get(key);
    if isinstance(value, bool) {
        return value;
    }
    return False;
}


def _object_list_value(data: dict[str, object], key: str) -> list[object] {
    value = data.get(key);
    if isinstance(value, list) {
        return value as list[object];
    }
    return [];
}


def events_from_result(result: ConnectorResult) -> list[CalendarEvent] {
    events_value = result.data.get("events");
    if isinstance(events_value, list) {
        return events_value as list[CalendarEvent];
    }
    return [];
}


def notes_from_result(result: ConnectorResult) -> list[VaultNote] {
    notes_value = result.data.get("notes");
    if isinstance(notes_value, list) {
        return notes_value as list[VaultNote];
    }
    return [];
}


def markdown_from_result(result: ConnectorResult) -> str {
    return _string_value(result.data, "markdown");
}


def source_references_from_result(result: ConnectorResult) -> list[str] {
    references_value = result.data.get("source_references");
    if isinstance(references_value, list) {
        return references_value as list[str];
    }
    return [];
}


def _event_from_raw(raw: dict[str, object]) -> CalendarEvent | None {
    event_id = _string_value(raw, "event_id");
    title = _string_value(raw, "title");
    start_at = _string_value(raw, "start_at");
    end_at = _string_value(raw, "end_at");
    source_ref = _string_value(raw, "source_ref");
    if not event_id or not title or not start_at or not end_at {
        return None;
    }
    attendees: list[str] = [];
    for attendee in _object_list_value(raw, "attendees") {
        if isinstance(attendee, str) and attendee.strip() {
            attendees.append(attendee.strip());
        }
    }
    return CalendarEvent(
        event_id=event_id,
        title=title,
        start_at=start_at,
        end_at=end_at,
        attendees=attendees,
        source_ref=source_ref
    );
}


def _typed_events(raw_events: list[dict[str, object]]) -> list[CalendarEvent] {
    events: list[CalendarEvent] = [];
    for raw_event in raw_events {
        event = _event_from_raw(raw_event);
        if event is not None {
            events.append(event);
        }
    }
    return events;
}


def read_fixture_calendar(reference_date: str = "") -> ConnectorResult {
    window = connector_host.tomorrow_window(reference_date);
    if not _bool_value(window, "success") {
        return ConnectorResult(success=False, error=_string_value(window, "error"));
    }
    calendar_date = _string_value(window, "calendar_date");
    events = [
        CalendarEvent(
            event_id="apex-design-review",
            title="Apex design review",
            start_at=f"{calendar_date}T09:30:00",
            end_at=f"{calendar_date}T10:15:00",
            attendees=["Lena Ortiz", "Sam Chen"],
            source_ref="fixture-calendar://apex-design-review"
        ),
        CalendarEvent(
            event_id="maya-onboarding",
            title="Maya onboarding",
            start_at=f"{calendar_date}T14:00:00",
            end_at=f"{calendar_date}T14:45:00",
            attendees=["Maya Patel", "Jordan Lee"],
            source_ref="fixture-calendar://maya-onboarding"
        )
    ];
    data: dict[str, object] = {};
    data["events"] = events;
    data["mode"] = "fixture";
    data["window_start"] = _string_value(window, "window_start");
    data["window_end"] = _string_value(window, "window_end");
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            "fixture: read 2 synthetic events in the bounded tomorrow window "
            "for QuaZe Demo."
        )
    );
}


def _live_calendar_result(raw_result: dict[str, object]) -> ConnectorResult {
    if not _bool_value(raw_result, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary=(
                "live: Calendar read failed before any event data was accepted."
            ),
            error=_string_value(raw_result, "error")
        );
    }
    raw_events_value = raw_result.get("events");
    if not isinstance(raw_events_value, list) {
        return ConnectorResult(
            success=False,
            evidence_summary="live: Calendar returned malformed results.",
            error="Calendar returned malformed event data for QuaZe Demo."
        );
    }
    raw_events = raw_events_value as list[dict[str, object]];
    events = _typed_events(raw_events);
    if not events or len(events) != len(raw_events) {
        return ConnectorResult(
            success=False,
            evidence_summary="live: Calendar returned malformed results.",
            error="Calendar returned malformed event data for QuaZe Demo."
        );
    }
    data: dict[str, object] = {};
    data["events"] = events;
    data["mode"] = "live";
    data["window_start"] = _string_value(raw_result, "window_start");
    data["window_end"] = _string_value(raw_result, "window_end");
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            f"live: read {len(events)} event(s) only from QuaZe Demo in the "
            "bounded tomorrow window."
        )
    );
}


def decode_live_calendar_output(output: str) -> ConnectorResult {
    return _live_calendar_result(connector_host.parse_calendar_output(output));
}


def read_live_calendar(reference_date: str = "") -> ConnectorResult {
    return _live_calendar_result(
        connector_host.live_calendar_records(DEMO_CALENDAR, reference_date)
    );
}


def read_calendar(
    connector_mode: str = "fixture", reference_date: str = "", available: bool = True
) -> ConnectorResult {
    if not available {
        return ConnectorResult(
            success=False,
            evidence_summary="unavailable: Calendar connector was not called.",
            error="Calendar connector is unavailable for this run."
        );
    }
    if connector_mode == "fixture" {
        return read_fixture_calendar(reference_date);
    }
    if connector_mode == "live" {
        return read_live_calendar(reference_date);
    }
    return ConnectorResult(
        success=False,
        evidence_summary="unavailable: unsupported Calendar connector mode.",
        error="connector_mode must be fixture or live."
    );
}


def _tokens(text: str) -> set[str] {
    normalized = re.sub(r"[^a-z0-9]+", " ", text.lower());
    return {
        token
        for token in normalized.split()
        if len(token) >= 3 and token not in MATCH_STOPWORDS
    };
}


def _meeting_tokens(meeting: CalendarEvent) -> set[str] {
    tokens = _tokens(meeting.title);
    for attendee in meeting.attendees {
        tokens.update(_tokens(attendee));
    }
    return tokens;
}


def _match_notes(
    meetings: list[CalendarEvent], raw_notes: list[dict[str, object]]
) -> list[VaultNote] {
    notes: list[VaultNote] = [];
    for raw_note in raw_notes {
        path = _string_value(raw_note, "path");
        title = _string_value(raw_note, "title");
        content = _string_value(raw_note, "content");
        if not path or not title or not content {
            continue;
        }
        title_tokens = _tokens(title);
        content_tokens = _tokens(content);
        meeting_ids: list[str] = [];
        for meeting in meetings {
            meeting_tokens = _meeting_tokens(meeting);
            title_matches = title_tokens.intersection(meeting_tokens);
            content_matches = content_tokens.intersection(meeting_tokens);
            required_content_matches = 1 if len(meeting_tokens) <= 1 else 2;
            if title_matches or len(content_matches) >= required_content_matches {
                meeting_ids.append(meeting.event_id);
            }
        }
        if meeting_ids {
            notes.append(
                VaultNote(
                    path=path,
                    title=title,
                    content=content,
                    meeting_ids=meeting_ids,
                    source_ref=f"vault://{path.replace(' ', '%20')}"
                )
            );
        }
    }
    return notes;
}


def _notes_result(
    host_result: dict[str, object], meetings: list[CalendarEvent], evidence_prefix: str
) -> ConnectorResult {
    if not _bool_value(host_result, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary=evidence_prefix + ": vault read failed.",
            error=_string_value(host_result, "error")
        );
    }
    raw_notes_value = host_result.get("notes");
    if not isinstance(raw_notes_value, list) {
        return ConnectorResult(
            success=False,
            evidence_summary=evidence_prefix + ": malformed vault results.",
            error="The dedicated demo vault returned malformed note data."
        );
    }
    raw_notes = raw_notes_value as list[dict[str, object]];
    notes = _match_notes(meetings, raw_notes);
    data: dict[str, object] = {};
    data["notes"] = notes;
    data["mode"] = evidence_prefix;
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            f"{evidence_prefix}: matched {len(notes)} relevant note(s) from "
            "the dedicated demo vault."
        )
    );
}


def _direct_vault_search(
    meetings: list[CalendarEvent], evidence_prefix: str
) -> ConnectorResult {
    return _notes_result(
        connector_host.direct_vault_notes(), meetings, evidence_prefix
    );
}


def discover_filesystem_mcp -> ConnectorResult {
    discovered = connector_host.discover_filesystem_mcp_command();
    if not _bool_value(discovered, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary=(
                "unavailable: official filesystem MCP server was not started."
            ),
            error=_string_value(discovered, "error")
        );
    }
    data: dict[str, object] = {};
    data["transport"] = "stdio";
    data["server"] = "@modelcontextprotocol/server-filesystem";
    data["allowed_root"] = DEMO_VAULT;
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            "mcp: discovered the installed official filesystem stdio server; "
            "calls will pass only the dedicated demo-vault root."
        )
    );
}


def search_vault(
    meetings: list[CalendarEvent],
    connector_mode: str = "fixture",
    available: bool = True,
    allow_fallback: bool = True
) -> ConnectorResult {
    if not available {
        return ConnectorResult(
            success=False,
            evidence_summary="unavailable: vault connector was not called.",
            error="Vault connector is unavailable for this run."
        );
    }
    if connector_mode == "fixture" {
        return _direct_vault_search(meetings, "fixture direct-filesystem");
    }
    if connector_mode == "direct" {
        return _direct_vault_search(meetings, "fallback direct-filesystem");
    }
    if connector_mode != "mcp" {
        return ConnectorResult(
            success=False,
            evidence_summary="unavailable: unsupported vault connector mode.",
            error="connector_mode must be fixture, direct, or mcp."
        );
    }

    mcp_result = _notes_result(
        connector_host.mcp_vault_notes(), meetings, "mcp official-filesystem-stdio"
    );
    if mcp_result.success or not allow_fallback {
        return mcp_result;
    }
    fallback = _direct_vault_search(
        meetings, "fallback direct-filesystem after MCP unavailable"
    );
    if fallback.success {
        fallback.evidence_summary = (
            fallback.evidence_summary + " MCP error: " + mcp_result.error
        );
    }
    return fallback;
}


def _context_excerpt(content: str) -> str {
    parts: list[str] = [];
    for line in content.splitlines() {
        stripped = line.strip();
        if stripped and not stripped.startswith("#") {
            parts.append(stripped.lstrip("-").strip());
        }
    }
    excerpt = " ".join(parts);
    if len(excerpt) > 420 {
        return excerpt[:417].rstrip() + "...";
    }
    return excerpt;
}


def draft_brief(
    meetings: list[CalendarEvent], notes: list[VaultNote]
) -> ConnectorResult {
    if not meetings {
        return ConnectorResult(
            success=False,
            evidence_summary="deterministic draft: no draft was produced.",
            error="At least one Calendar event is required to draft the brief."
        );
    }
    lines: list[str] = [
        "# Tomorrow Brief",
        "",
        "Prepared from the bounded QuaZe Demo Calendar and dedicated demo vault.",
        ""
    ];
    references: list[str] = [];
    for meeting in meetings {
        lines.extend(
            [
                f"## {meeting.title}",
                "",
                f"- Time: {meeting.start_at} to {meeting.end_at}",
                (
                    "- Attendees: " + (
                        ", ".join(meeting.attendees)
                            if meeting.attendees
                            else "None listed"
                    )
                ),
                f"- Meeting source: `{meeting.source_ref}`"
            ]
        );
        if meeting.source_ref not in references {
            references.append(meeting.source_ref);
        }
        matching_notes = [
            note
            for note in notes
            if meeting.event_id in note.meeting_ids
        ];
        if matching_notes {
            for note in matching_notes {
                lines.append(
                    f"- Vault context ({note.title}): {_context_excerpt(note.content)}"
                );
                lines.append(f"- Note source: `{note.source_ref}`");
                if note.source_ref not in references {
                    references.append(note.source_ref);
                }
            }
            lines.append(
                "- Missing context: confirm the decision owner, desired "
                "decision, and unresolved questions before the meeting."
            );
        } else {
            lines.append(
                "- Missing context: no relevant note was found in the dedicated "
                "demo vault."
            );
        }
        lines.append("");
    }
    lines.extend(["## Sources", ""]);
    for reference in references {
        lines.append(f"- `{reference}`");
    }
    markdown = "\n".join(lines).rstrip() + "\n";
    data: dict[str, object] = {};
    data["markdown"] = markdown;
    data["source_references"] = references;
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            f"deterministic draft: cited {len(references)} meeting/note source(s) "
            "and marked missing context."
        )
    );
}


def resolve_demo_vault_path(
    relative_path: str, must_exist: bool = False
) -> ConnectorResult {
    resolved = connector_host.resolve_vault_path(relative_path, must_exist);
    if not _bool_value(resolved, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary="rejected: path was not accepted by the vault boundary.",
            error=_string_value(resolved, "error")
        );
    }
    data: dict[str, object] = {};
    data["path"] = _string_value(resolved, "path");
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary="contained: path resolved inside the dedicated demo vault."
    );
}


def save_brief(
    markdown: str, source_references: list[str], relative_path: str = BRIEF_FILENAME
) -> ConnectorResult {
    if not markdown.strip() {
        return ConnectorResult(
            success=False,
            evidence_summary="save rejected: draft content was empty.",
            error="A non-empty approved brief is required before saving."
        );
    }
    saved = connector_host.save_vault_artifact(relative_path, markdown);
    if not _bool_value(saved, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary="save rejected: no artifact was accepted.",
            error=_string_value(saved, "error")
        );
    }
    data: dict[str, object] = {};
    data["path"] = _string_value(saved, "path");
    data["content_hash"] = _string_value(saved, "content_hash");
    data["created"] = _bool_value(saved, "created");
    data["source_references"] = source_references;
    action = "created atomically" if _bool_value(saved, "created") else "reused";
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary=(
            f"artifact: {action} the idempotent {BRIEF_FILENAME} content hash."
        )
    );
}


def open_saved_brief(
    relative_path: str = BRIEF_FILENAME, launch_gui: bool = False
) -> ConnectorResult {
    opened = connector_host.open_obsidian_artifact(relative_path, launch_gui);
    if not _bool_value(opened, "success") {
        return ConnectorResult(
            success=False,
            evidence_summary="unavailable: Obsidian did not open the artifact.",
            error=_string_value(opened, "error")
        );
    }
    data: dict[str, object] = {};
    data["opened"] = True;
    return ConnectorResult(
        success=True,
        data=data,
        evidence_summary="live: opened the generated artifact in Obsidian."
    );
}
