"""Graph-walking execution for persisted QuaZe runs."""

import from contracts {
    ExecutionFlow,
    HasRun,
    HasStep,
    Run,
    RunState,
    RunStep,
    StepForBlock,
    StepState
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
import from graph_store {
    attach_artifact,
    now_iso,
    record_step_event,
    request_approval
}


def _owning_run(step: RunStep) -> Run | None {
    runs = [step<-:HasStep:<-];
    return runs[0] if runs else None;
}


def _next_step(run: Run, step: RunStep) -> RunStep | None {
    blocks = [step->:StepForBlock:->];
    if not blocks {
        return None;
    }
    next_blocks = [blocks[0]->:ExecutionFlow:->];
    if not next_blocks {
        return None;
    }
    next_block_id = next_blocks[0].block_id;
    for candidate in [run->:HasStep:->] {
        if candidate.block_id == next_block_id {
            return candidate;
        }
    }
    return None;
}


def _context_string(run: Run, key: str) -> str {
    value = run.context.get(key);
    return value if isinstance(value, str) else "";
}


def _context_strings(run: Run, key: str) -> list[str] {
    value = run.context.get(key);
    return value as list[str] if isinstance(value, list) else [];
}


def _begin_step(run: Run, step: RunStep) {
    step.state = StepState.RUNNING;
    step.attempt += 1;
    step.started_at = now_iso();
    step.completed_at = "";
    step.error = "";
    record_step_event(run, step, "step_started", f"{step.title} started.");
}


def _succeed_step(run: Run, step: RunStep, evidence_summary: str) {
    step.state = StepState.SUCCEEDED;
    step.completed_at = now_iso();
    step.evidence_summary = evidence_summary;
    record_step_event(run, step, "step_succeeded", evidence_summary);
}


def _skip_step(run: Run, step: RunStep, evidence_summary: str) {
    step.state = StepState.SKIPPED;
    step.completed_at = now_iso();
    step.evidence_summary = evidence_summary;
    record_step_event(run, step, "step_skipped", evidence_summary);
}


def _fail_step(run: Run, step: RunStep, error: str, evidence_summary: str = "") {
    step.state = StepState.FAILED;
    step.completed_at = now_iso();
    step.error = error;
    step.evidence_summary = evidence_summary;
    run.state = RunState.FAILED;
    record_step_event(
        run,
        step,
        "step_failed",
        evidence_summary + (" " if evidence_summary else "") + error
    );
}


walker WorkflowExecutorWalker {
    has connector_mode: str = "fixture",
        meetings: list[CalendarEvent] = [],
        notes: list[VaultNote] = [],
        draft_markdown: str = "",
        source_references: list[str] = [];

    can begin with Run entry {
        self.connector_mode = _context_string(here, "connector_mode");
        steps = [here->:HasStep:->];
        steps.sort(key=lambda (step: RunStep) { step.position; });
        if not steps {
            here.state = RunState.FAILED;
            disengage;
        }
        visit steps[0];
    }

    can execute_step with RunStep entry {
        run = _owning_run(here);
        if run is None {
            disengage;
        }

        if here.state in [StepState.SUCCEEDED, StepState.SKIPPED] {
            next_completed_step = _next_step(run, here);
            if next_completed_step is not None {
                visit next_completed_step;
            }
            return;
        }

        if run.state == RunState.FAILED {
            disengage;
        }

        _begin_step(run, here);

        if here.block_id == "run-now" {
            _succeed_step(
                run, here, "Run request accepted for the persisted workflow."
            );
        } elif here.block_id == "read-calendar" {
            calendar_result = read_calendar(connector_mode=self.connector_mode);
            if not calendar_result.success {
                _fail_step(
                    run, here, calendar_result.error, calendar_result.evidence_summary
                );
                disengage;
            }
            self.meetings = events_from_result(calendar_result);
            if not self.meetings {
                _fail_step(
                    run,
                    here,
                    "Calendar returned no usable meeting records.",
                    calendar_result.evidence_summary
                );
                disengage;
            }
            _succeed_step(run, here, calendar_result.evidence_summary);
        } elif here.block_id == "search-vault" {
            vault_result = search_vault(
                meetings=self.meetings,
                connector_mode=(
                    "fixture" if self.connector_mode == "fixture" else "mcp"
                ),
                allow_fallback=True
            );
            if not vault_result.success {
                _fail_step(
                    run, here, vault_result.error, vault_result.evidence_summary
                );
                disengage;
            }
            self.notes = notes_from_result(vault_result);
            _succeed_step(run, here, vault_result.evidence_summary);
        } elif here.block_id == "draft-brief" {
            draft_result = draft_brief(self.meetings, self.notes);
            if not draft_result.success {
                _fail_step(
                    run, here, draft_result.error, draft_result.evidence_summary
                );
                disengage;
            }
            self.draft_markdown = markdown_from_result(draft_result);
            self.source_references = source_references_from_result(draft_result);
            _succeed_step(run, here, draft_result.evidence_summary);
        } elif here.block_id == "approval" {
            run.context["draft_markdown"] = self.draft_markdown;
            run.context["source_references"] = self.source_references;
            meeting_titles = ", ".join([meeting.title for meeting in self.meetings]);
            request_approval(
                run,
                here,
                (
                    f"Review the cited brief for {meeting_titles}. "
                    "Approve before QuaZe writes Tomorrow Brief.md."
                )
            );
            disengage;
        } elif here.block_id == "save-brief" {
            draft_markdown = _context_string(run, "draft_markdown");
            source_references = _context_strings(run, "source_references");
            save_result = save_brief(draft_markdown, source_references);
            if not save_result.success {
                _fail_step(run, here, save_result.error, save_result.evidence_summary);
                disengage;
            }
            artifact_path = _context_result_string(save_result.data, "path");
            artifact_hash = _context_result_string(save_result.data, "content_hash");
            _succeed_step(run, here, save_result.evidence_summary);
            attach_artifact(run, artifact_path, artifact_hash, source_references);
        } elif here.block_id == "open-result" {
            if self.connector_mode != "live" {
                _skip_step(
                    run,
                    here,
                    "Fixture mode saved the artifact; Obsidian launch was skipped."
                );
                run.state = RunState.SUCCEEDED;
                disengage;
            }
            open_result = open_saved_brief(launch_gui=True);
            if not open_result.success {
                _fail_step(run, here, open_result.error, open_result.evidence_summary);
                disengage;
            }
            _succeed_step(run, here, open_result.evidence_summary);
            run.state = RunState.SUCCEEDED;
        } else {
            _fail_step(run, here, f"Unsupported persisted block ID: {here.block_id}.");
            disengage;
        }

        next_step = _next_step(run, here);
        if next_step is not None {
            visit next_step;
        } elif run.state == RunState.RUNNING {
            run.state = RunState.SUCCEEDED;
        }
    }
}


def _context_result_string(data: dict[str, object], key: str) -> str {
    value = data.get(key);
    return value if isinstance(value, str) else "";
}
