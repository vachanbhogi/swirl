"""Command-line adapter used by Swirl's Tauri native process."""

import json;
import sys;
import from backend.workflow_agent {
    PromptToWorkflowWalker, plan_workflow, transform_text
}
import from backend.code_generator { JacCodeGeneratorWalker }
import from backend.mac_control { classify_mac_action, validate_mac_action }
import from backend.mcp_bridge {
    initialize_request, tools_list_request, tool_call_request, validate_transport
}


def emit(payload: any) {
    print("__SWIRL_JSON__" + json.dumps(payload));
}


def read_payload(path: str) -> dict {
    with open(path, "r", encoding="utf-8") as handle {
        value = json.load(handle);
    }
    if not isinstance(value, dict) {
        raise ValueError("Swirl runtime input must be a JSON object");
    }
    return value as dict;
}


def run_command(command: str, payload: dict) -> dict {
    if command == "prompt" or command == "prompt-llm" {
        prompt: str = str(payload.get("prompt", ""));
        if not prompt.strip() {
            raise ValueError("Prompt cannot be empty");
        }
        prompt_result = root spawn PromptToWorkflowWalker(
            user_prompt=prompt,
            use_llm=command == "prompt-llm",
        );
        return prompt_result.reports[0].to_dict();
    }
    if command == "llm-transform" {
        return {
            "text": transform_text(
                str(payload.get("text", "")),
                str(payload.get("instruction", "Summarize concisely")),
            )
        };
    }
    if command == "plan" {
        return {"plan": plan_workflow(payload)};
    }
    if command == "code" {
        code_result = root spawn JacCodeGeneratorWalker(workflow=payload);
        return {"source": code_result.reports[0]};
    }
    if command == "mac-policy" {
        app: str = str(payload.get("app", ""));
        action: str = str(payload.get("action", ""));
        return {
            "valid": validate_mac_action(app, action),
            "policy": classify_mac_action(app, action).to_dict(),
        };
    }
    if command == "mcp-initialize" {
        return initialize_request(str(payload.get("clientVersion", "1.0.0"))).to_dict();
    }
    if command == "mcp-tools-list" {
        return tools_list_request().to_dict();
    }
    if command == "mcp-call" {
        return tool_call_request(
            str(payload.get("toolName", "")),
            payload.get("arguments", {}) as dict,
        ).to_dict();
    }
    if command == "mcp-validate" {
        return {"valid": validate_transport(payload)};
    }
    raise ValueError(f"Unknown Swirl runtime command: {command}");
}


with entry:__main__ {
    try {
        if len(sys.argv) != 3 {
            raise ValueError("Usage: jac run backend/swirl_runtime.jac <command> <payload.json>");
        }
        emit({"ok": True, "data": run_command(sys.argv[1], read_payload(sys.argv[2]))});
    } except Exception as error {
        emit({"ok": False, "error": str(error)});
        sys.exit(1);
    }
}
