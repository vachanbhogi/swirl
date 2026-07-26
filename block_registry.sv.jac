"""Typed block registry and the single execution boundary for QuaZe."""

import hashlib;
import json;
import from contracts {
    Block,
    BlockDefinitionSpec,
    BlockSpec,
    ConfigFieldSpec,
    ConnectorRequirementSpec,
    EffectKind,
    EffectPolicySpec,
    PortSpec,
    RetryPolicySpec
}
import from connectors {
    CalendarEvent,
    VaultNote,
    draft_brief,
    events_from_result,
    markdown_from_result,
    notes_from_result,
    open_saved_brief,
    read_calendar,
    save_brief,
    search_vault,
    source_references_from_result
}
import from safety { sanitize_public_message }

obj BlockExecutionResult {
    has success: bool = False,
        outcome: str = "failed",
        evidence_summary: str = "",
        error: str = "",
        error_code: str = "",
        context_updates: dict[str, object] = {},
        evidence_snapshot_hashes: list[str] = [],
        effect_kind: EffectKind = EffectKind.NONE,
        approval_prompt: str = "",
        artifact_path: str = "",
        artifact_hash: str = "",
        artifact_created: bool = False,
        write_state: str = "";
}


def _port(name: str, label: str, data_type: str) -> PortSpec {
    return PortSpec(name=name, label=label, data_type=data_type);
}


def _config(
    key: str,
    label: str,
    default_value: str,
    allowed_values: list[str],
    help_text: str
) -> ConfigFieldSpec {
    return ConfigFieldSpec(
        key=key,
        label=label,
        value_type="enum",
        required=True,
        default_value=default_value,
        allowed_values=allowed_values,
        help_text=help_text
    );
}


def block_catalog -> list[BlockDefinitionSpec] {
    return [
        BlockDefinitionSpec(
            block_type="run_now",
            version=1,
            config_version=1,
            handler_version=1,
            title="Run Now",
            description="Starts a workflow only when the user chooses Run.",
            category="Trigger",
            handler="accept_run",
            output_ports=[_port("run_request", "Run request", "trigger")],
            retry_policy=RetryPolicySpec(max_attempts=1, idempotent=True),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.NONE,
                preview_allowed=True
            ),
            audit_fields=["accepted_at"],
            is_trigger=True
        ),
        BlockDefinitionSpec(
            block_type="read_calendar",
            version=1,
            config_version=1,
            handler_version=1,
            title="Read Calendar",
            description="Reads tomorrow from the dedicated QuaZe Demo calendar.",
            category="Read",
            handler="read_demo_calendar",
            input_ports=[_port("run_request", "Run request", "trigger")],
            output_ports=[_port("meetings", "Meetings", "calendar_events")],
            config_schema=[
                _config(
                    "calendar",
                    "Calendar",
                    "QuaZe Demo",
                    ["QuaZe Demo"],
                    "Only the dedicated synthetic demo calendar is allowed."
                ),
                _config(
                    "range",
                    "Date range",
                    "tomorrow",
                    ["tomorrow"],
                    "The live adapter is bounded to tomorrow."
                )
            ],
            permissions=["calendar.read.demo"],
            connector_requirements=[
                ConnectorRequirementSpec(
                    connector_id="calendar", permission="calendar.read.demo"
                )
            ],
            retry_policy=RetryPolicySpec(
                max_attempts=2, idempotent=True, backoff_ms=250
            ),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.READ,
                preview_allowed=True,
                target_scope="QuaZe Demo/tomorrow",
                maximum_affected_items=100
            ),
            audit_fields=["connector_mode", "window", "record_count"]
        ),
        BlockDefinitionSpec(
            block_type="search_vault",
            version=1,
            config_version=1,
            handler_version=1,
            title="Search Vault",
            description="Finds relevant notes inside the dedicated demo vault.",
            category="Read",
            handler="search_demo_vault",
            input_ports=[_port("meetings", "Meetings", "calendar_events")],
            output_ports=[_port("matched_notes", "Matched notes", "vault_notes")],
            config_schema=[
                _config(
                    "vault",
                    "Vault",
                    "fixtures/demo-vault",
                    ["fixtures/demo-vault"],
                    "Reads remain path-contained inside the repository demo vault."
                )
            ],
            permissions=["vault.read.demo"],
            connector_requirements=[
                ConnectorRequirementSpec(
                    connector_id="vault", permission="vault.read.demo"
                )
            ],
            retry_policy=RetryPolicySpec(
                max_attempts=2, idempotent=True, backoff_ms=250
            ),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.READ,
                preview_allowed=True,
                target_scope="fixtures/demo-vault",
                maximum_affected_items=100
            ),
            audit_fields=["connector_mode", "matched_paths", "fallback_state"]
        ),
        BlockDefinitionSpec(
            block_type="draft_brief",
            version=1,
            config_version=1,
            handler_version=1,
            title="Draft Brief",
            description="Builds a deterministic cited Markdown brief.",
            category="Transform",
            handler="draft_cited_brief",
            input_ports=[
                _port("meetings", "Meetings", "calendar_events"),
                _port("matched_notes", "Matched notes", "vault_notes")
            ],
            output_ports=[
                _port("brief_markdown", "Draft brief", "markdown_document")
            ],
            retry_policy=RetryPolicySpec(max_attempts=1, idempotent=True),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.TRANSFORM,
                preview_allowed=True
            ),
            audit_fields=["source_references", "content_hash"]
        ),
        BlockDefinitionSpec(
            block_type="approval",
            version=1,
            config_version=1,
            handler_version=1,
            title="Approval",
            description="Pauses the persisted run before the write.",
            category="Control",
            handler="request_human_approval",
            input_ports=[
                _port("brief_markdown", "Draft brief", "markdown_document")
            ],
            output_ports=[
                _port("approved_brief", "Approved brief", "markdown_document")
            ],
            permissions=["human.approval"],
            retry_policy=RetryPolicySpec(max_attempts=1, idempotent=False),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.APPROVAL,
                preview_allowed=True
            ),
            audit_fields=["requested_at", "decision", "decided_at"]
        ),
        BlockDefinitionSpec(
            block_type="save_brief",
            version=1,
            config_version=1,
            handler_version=1,
            title="Save Brief",
            description="Writes one idempotent artifact inside the demo vault.",
            category="Write",
            handler="save_demo_brief",
            input_ports=[
                _port("approved_brief", "Approved brief", "markdown_document")
            ],
            output_ports=[_port("artifact", "Saved artifact", "file_artifact")],
            config_schema=[
                _config(
                    "filename",
                    "Filename",
                    "Tomorrow Brief.md",
                    ["Tomorrow Brief.md"],
                    "This release writes only the bounded demo artifact."
                )
            ],
            permissions=["vault.write.demo"],
            connector_requirements=[
                ConnectorRequirementSpec(
                    connector_id="filesystem", permission="vault.write.demo"
                )
            ],
            retry_policy=RetryPolicySpec(
                max_attempts=2, idempotent=True, backoff_ms=250
            ),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.WRITE,
                requires_approval=True,
                target_scope="fixtures/demo-vault/Tomorrow Brief.md",
                maximum_affected_items=1
            ),
            audit_fields=["path", "content_hash", "source_references"],
            allow_multiple=False
        ),
        BlockDefinitionSpec(
            block_type="open_result",
            version=1,
            config_version=1,
            handler_version=1,
            title="Open Result",
            description="Reveals the saved artifact in Obsidian when available.",
            category="Output",
            handler="open_demo_result",
            input_ports=[_port("artifact", "Saved artifact", "file_artifact")],
            output_ports=[
                _port("opened_artifact", "Opened artifact", "application_result")
            ],
            permissions=["obsidian.open"],
            connector_requirements=[
                ConnectorRequirementSpec(
                    connector_id="obsidian",
                    permission="obsidian.open",
                    required=False
                )
            ],
            retry_policy=RetryPolicySpec(max_attempts=1, idempotent=False),
            effect_policy=EffectPolicySpec(
                kind=EffectKind.OPEN,
                target_scope="fixtures/demo-vault/Tomorrow Brief.md",
                maximum_affected_items=1
            ),
            audit_fields=["launch_state"]
        )
    ];
}


def block_definition(block_type: str) -> BlockDefinitionSpec | None {
    for definition in block_catalog() {
        if definition.block_type == block_type {
            return definition;
        }
    }
    return None;
}


def supported_block_types -> list[str] {
    return [definition.block_type for definition in block_catalog()];
}


def default_connector_names -> list[str] {
    return ["calendar", "vault", "filesystem", "obsidian"];
}


def build_block_spec(block_type: str, block_id: str) -> BlockSpec | None {
    definition = block_definition(block_type);
    if definition is None {
        return None;
    }
    config: dict[str, object] = {};
    for field in definition.config_schema {
        config[field.key] = field.default_value;
    }
    return BlockSpec(
        id=block_id,
        block_type=definition.block_type,
        block_version=definition.version,
        config_version=definition.config_version,
        title=definition.title,
        config=config,
        inputs=[port.name for port in definition.input_ports],
        outputs=[port.name for port in definition.output_ports],
        permissions=[permission for permission in definition.permissions]
    );
}


def _context_meetings(context: dict[str, object]) -> list[CalendarEvent] {
    value = context.get("meetings");
    return value as list[CalendarEvent] if isinstance(value, list) else [];
}


def _context_notes(context: dict[str, object]) -> list[VaultNote] {
    value = context.get("matched_notes");
    return value as list[VaultNote] if isinstance(value, list) else [];
}


def _context_string(context: dict[str, object], key: str) -> str {
    value = context.get(key);
    return value if isinstance(value, str) else "";
}


def _context_strings(context: dict[str, object], key: str) -> list[str] {
    value = context.get(key);
    return value as list[str] if isinstance(value, list) else [];
}


def _result_string(data: dict[str, object], key: str) -> str {
    value = data.get(key);
    return value if isinstance(value, str) else "";
}


def _result_bool(data: dict[str, object], key: str) -> bool {
    value = data.get(key);
    return value if isinstance(value, bool) else False;
}

def _hash_payload(payload: object) -> str {
    return hashlib.sha256(
        json.dumps(
            payload,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True
        ).encode("utf-8")
    ).hexdigest();
}


def _calendar_evidence_hashes(events: list[CalendarEvent]) -> list[str] {
    hashes: list[str] = [];
    for event in events {
        hashes.append(_hash_payload({
            "event_id": event.event_id,
            "title": event.title,
            "start_at": event.start_at,
            "end_at": event.end_at,
            "attendees": event.attendees,
            "source_ref": event.source_ref
        }));
    }
    return hashes;
}


def _vault_evidence_hashes(notes: list[VaultNote]) -> list[str] {
    hashes: list[str] = [];
    for note in notes {
        hashes.append(_hash_payload({
            "path": note.path,
            "title": note.title,
            "content": note.content,
            "meeting_ids": note.meeting_ids,
            "source_ref": note.source_ref
        }));
    }
    return hashes;
}


def _normalized_connector_mode(raw_mode: str, requested_mode: str) -> str {
    if raw_mode.startswith("fixture") {
        return "fixture";
    }
    if raw_mode.startswith("fallback") {
        return "fallback";
    }
    if raw_mode.startswith("mcp") or raw_mode == "live" {
        return "live";
    }
    return requested_mode if requested_mode else "unavailable";
}


def execute_registered_block(
    block: Block, context: dict[str, object], connector_mode: str
) -> BlockExecutionResult {
    definition = block_definition(block.block_type);
    if definition is None or block.block_version != definition.version {
        return BlockExecutionResult(
            error=(
                f"Unsupported persisted block {block.block_type} "
                f"version {block.block_version}."
            )
        );
    }

    if definition.handler == "accept_run" {
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary="Run request accepted for the persisted workflow.",
            context_updates={"run_request": "accepted"},
            effect_kind=EffectKind.NONE
        );
    }

    if definition.handler == "read_demo_calendar" {
        calendar_result = read_calendar(connector_mode=connector_mode);
        meetings = events_from_result(calendar_result);
        if not calendar_result.success or not meetings {
            return BlockExecutionResult(
                error=(
                    sanitize_public_message(calendar_result.error)
                        if calendar_result.error
                        else "Calendar returned no usable meeting records."
                ),
                evidence_summary=sanitize_public_message(
                    calendar_result.evidence_summary, ""
                ),
                error_code=calendar_result.error_code
            );
        }
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary=calendar_result.evidence_summary,
            context_updates={
                "meetings": meetings,
                "calendar_mode": _normalized_connector_mode(
                    _result_string(calendar_result.data, "mode"), connector_mode
                )
            },
            evidence_snapshot_hashes=_calendar_evidence_hashes(meetings),
            effect_kind=EffectKind.READ
        );
    }

    if definition.handler == "search_demo_vault" {
        meetings = _context_meetings(context);
        vault_result = search_vault(
            meetings=meetings,
            connector_mode="fixture" if connector_mode == "fixture" else "mcp",
            allow_fallback=True
        );
        if not vault_result.success {
            return BlockExecutionResult(
                error=sanitize_public_message(vault_result.error),
                evidence_summary=sanitize_public_message(
                    vault_result.evidence_summary, ""
                ),
                error_code=vault_result.error_code
            );
        }
        notes = notes_from_result(vault_result);
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary=vault_result.evidence_summary,
            context_updates={
                "matched_notes": notes,
                "vault_mode": _normalized_connector_mode(
                    _result_string(vault_result.data, "mode"), connector_mode
                )
            },
            evidence_snapshot_hashes=_vault_evidence_hashes(notes),
            effect_kind=EffectKind.READ
        );
    }

    if definition.handler == "draft_cited_brief" {
        draft_result = draft_brief(
            _context_meetings(context), _context_notes(context)
        );
        if not draft_result.success {
            return BlockExecutionResult(
                error=sanitize_public_message(draft_result.error),
                evidence_summary=sanitize_public_message(
                    draft_result.evidence_summary, ""
                ),
                error_code=draft_result.error_code
            );
        }
        markdown = markdown_from_result(draft_result);
        source_references = source_references_from_result(draft_result);
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary=draft_result.evidence_summary,
            context_updates={
                "brief_markdown": markdown,
                "source_references": source_references,
                "transform_mode": "deterministic"
            },
            evidence_snapshot_hashes=[
                _hash_payload(markdown),
                _hash_payload(source_references)
            ],
            effect_kind=EffectKind.TRANSFORM
        );
    }

    if definition.handler == "request_human_approval" {
        meetings = _context_meetings(context);
        meeting_titles = ", ".join([meeting.title for meeting in meetings]);
        approval_subject = (
            f"the synthetic fixture meetings ({meeting_titles})"
                if connector_mode == "fixture"
                else "the redacted live-data proposal"
        );
        return BlockExecutionResult(
            success=True,
            outcome="awaiting_approval",
            evidence_summary="Draft ready for a persisted approval decision.",
            effect_kind=EffectKind.APPROVAL,
            approval_prompt=(
                f"Review the cited brief for {approval_subject}. "
                "Approve before QuaZe writes Tomorrow Brief.md."
            )
        );
    }

    if definition.handler == "save_demo_brief" {
        approved_brief = _context_string(context, "approved_brief");
        source_references = _context_strings(context, "source_references");
        saved = save_brief(
            approved_brief,
            source_references,
            expected_prior_hash=_context_string(context, "expected_prior_hash")
        );
        if not saved.success {
            return BlockExecutionResult(
                error=sanitize_public_message(saved.error),
                error_code=saved.error_code,
                evidence_summary=sanitize_public_message(
                    saved.evidence_summary, ""
                )
            );
        }
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary=saved.evidence_summary,
            context_updates={
                "artifact_path": _result_string(saved.data, "path"),
                "artifact_hash": _result_string(saved.data, "content_hash"),
                "write_state": _result_string(saved.data, "write_state")
            },
            artifact_path=_result_string(saved.data, "path"),
            artifact_hash=_result_string(saved.data, "content_hash"),
            artifact_created=_result_bool(saved.data, "created"),
            write_state=_result_string(saved.data, "write_state"),
            effect_kind=(
                EffectKind.NONE
                    if _result_string(saved.data, "write_state") == "no_change"
                    else EffectKind.WRITE
            )
        );
    }

    if definition.handler == "open_demo_result" {
        if connector_mode != "live" {
            return BlockExecutionResult(
                success=True,
                outcome="skipped",
                effect_kind=EffectKind.NONE,
                evidence_summary=(
                    "Fixture mode saved the artifact; Obsidian launch was skipped."
                )
            );
        }
        opened = open_saved_brief(launch_gui=True);
        if not opened.success {
            return BlockExecutionResult(
                error=sanitize_public_message(opened.error),
                evidence_summary=sanitize_public_message(
                    opened.evidence_summary, ""
                ),
                error_code=opened.error_code
            );
        }
        return BlockExecutionResult(
            success=True,
            outcome="succeeded",
            evidence_summary=opened.evidence_summary,
            effect_kind=EffectKind.OPEN
        );
    }

    return BlockExecutionResult(
        error=f"Block handler {definition.handler} is not implemented."
    );
}
