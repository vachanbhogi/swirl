"""Compile plain-language goals into QuaZe's currently supported workflow."""

import os;
import httpx;
import from jaclang.byllm.lib { ByLLMError }
import from contracts { DemoState }
import from workflow { golden_workflow_spec, initial_demo_state }

enum AllowedBlockType {
    RUN_NOW = "run_now",
    READ_CALENDAR = "read_calendar",
    SEARCH_VAULT = "search_vault",
    DRAFT_BRIEF = "draft_brief",
    APPROVAL = "approval",
    SAVE_BRIEF = "save_brief",
    OPEN_RESULT = "open_result"
}

obj HostedWorkflowDraft {
    has block_types: list[AllowedBlockType];
}

sem HostedWorkflowDraft = """
QuaZe is a prompt-first agentic workflow builder for non-technical users. This
release proves the system through its first supported template: a
meeting-preparation workflow made only from QuaZe's seven allowlisted block
types. The workflow must include every supported block exactly once and keep
the safe execution order: read before draft, approval immediately before save,
and open only after save.
""";

sem compile_hosted_workflow = """
Interpret the user's requested outcome and compile it into QuaZe's currently
supported meeting-preparation block sequence. Do not imply that this build can
generate arbitrary workflows. Do not invent tools, omit safety gates, or add
capabilities.
""";

def compile_hosted_workflow(user_prompt: str) -> HostedWorkflowDraft by llm(
    max_output_retries=1
);

def canonical_block_types -> list[str] {
    return [
        "run_now",
        "read_calendar",
        "search_vault",
        "draft_brief",
        "approval",
        "save_brief",
        "open_result"
    ];
}

def _draft_block_types(draft: HostedWorkflowDraft) -> list[str] {
    return [str(block_type.value) for block_type in draft.block_types];
}

def _hosted_draft_is_safe(draft: HostedWorkflowDraft) -> bool {
    return _draft_block_types(draft) == canonical_block_types();
}

def _prompt_matches_golden_intent(user_prompt: str) -> bool {
    normalized = user_prompt.strip().lower();
    if not normalized {
        return False;
    }
    unsupported_terms = [
        "delete",
        "email",
        "mail",
        "shell",
        "terminal",
        "calendar event",
        "send message"
    ];
    if any(term in normalized for term in unsupported_terms) {
        return False;
    }
    return any(
        term in normalized for term in ["meeting", "calendar", "vault", "brief"]
    );
}

def _fallback_state(notice: str) -> DemoState {
    return initial_demo_state(
        compiler_mode="deterministic_fallback", compiler_notice=notice
    );
}

def compile_prompt_for_mode(user_prompt: str, hosted_enabled: bool) -> DemoState {
    if not hosted_enabled {
        if not _prompt_matches_golden_intent(user_prompt) {
            return _fallback_state(
                "The prompt requested an unsupported or empty workflow. "
                "QuaZe loaded its supported meeting-prep workflow in labeled "
                "deterministic fallback mode."
            );
        }
        return initial_demo_state(
            compiler_mode="deterministic",
            compiler_notice=(
                "The supported meeting-prep workflow was loaded in "
                "deterministic mode. Hosted compilation is disabled."
            )
        );
    }

    if not user_prompt.strip() {
        return _fallback_state(
            "The prompt was empty. QuaZe loaded its supported "
            "meeting-prep workflow in deterministic fallback mode."
        );
    }

    try {
        draft = compile_hosted_workflow(user_prompt);
        if not _hosted_draft_is_safe(draft) {
            return _fallback_state(
                "Hosted output did not match QuaZe's seven-block "
                "allowlist. The supported meeting-prep workflow was loaded "
                "in deterministic fallback mode."
            );
        }
        workflow = golden_workflow_spec();
        return DemoState(
            workflow=workflow,
            validation=workflow.validation,
            compiler_mode="hosted",
            compiler_notice=(
                "The prompt was compiled into QuaZe's currently supported "
                "seven-block meeting-prep workflow."
            )
        );
    } except (ByLLMError, ConnectionError, TimeoutError, OSError, httpx.HTTPError) {
        return _fallback_state(
            "Hosted compilation was unavailable. QuaZe loaded its "
            "supported meeting-prep workflow in deterministic fallback "
            "mode."
        );
    }
}

def compile_prompt_state(user_prompt: str) -> DemoState {
    hosted_enabled = (
        os.getenv("QUAZE_ENABLE_HOSTED_COMPILER", "0").strip().lower() in [
            "1",
            "true",
            "yes"
        ]
    );
    return compile_prompt_for_mode(user_prompt, hosted_enabled);
}
