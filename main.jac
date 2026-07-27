"""Swirl Jac full-stack entry point."""

import from backend.workflow_agent { PromptToWorkflowWalker }
import "./frontend/src/index.css";
import from .frontend.client.App { SwirlApp }
import from .frontend.client.NotchOverlay { NotchOverlay }


def:pub app -> JsxElement {
    location: any = window.location;  # jac:ignore[W2001]
    if location.hash == "#/notch" or location.pathname == "/notch" {
        return <NotchOverlay />;
    }
    return <SwirlApp />;
}


with entry {
    result = root spawn PromptToWorkflowWalker(
        user_prompt="Organize my Desktop files and create an Apple Note report"
    );
    print(result.reports[0].to_dict());
}
