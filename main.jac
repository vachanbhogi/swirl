"""Swirl Jac runtime smoke-test entry point."""

import from backend.workflow_agent { PromptToWorkflowWalker }


with entry {
    result = root spawn PromptToWorkflowWalker(
        user_prompt="Organize my Desktop files and create an Apple Note report"
    );
    print(result.reports[0].to_dict());
}
