"""Command-line adapter used by Swirl's Tauri native process."""

import json;
import sys;
import from backend.workflow_agent {
    PromptToWorkflowWalker, plan_workflow, transform_text
}
import from backend.code_generator { JacCodeGeneratorWalker }
import from backend.mac_control {
    classify_mac_action, validate_mac_action,
    build_applescript, validate_restricted_applescript
}
import from backend.mcp_bridge {
    initialize_request, tools_list_request, tool_call_request,
    validate_transport, parse_tools_response, validate_tool_arguments,
    validate_server_name, notifications_initialized_request,
    resources_list_request, prompts_list_request,
    builtin_mcp_servers, builtin_mcp_server
}
import from backend.models {
    WorkflowDocument, ExecutionEvent, ExecutionSummary
}
import from backend.storage {
    save_workflow, load_workflow, list_workflows, delete_workflow, save_trace
}
import from backend.block_definitions {
    BLOCK_CATEGORIES, BLOCK_LIBRARY, workflow_presets,
    default_starter_workflow, get_block_by_type, get_blocks_by_category,
    category_color
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
    print(f"[Swirl][Jac] runtime command: {command}");
    # --- Prompt & Workflow Planning ---
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

    # --- Workflow Validation ---
    if command == "validate" {
        doc = WorkflowDocument(
            nodes=payload.get("nodes", []) as list,
            edges=payload.get("edges", []) as list,
        );
        try {
            doc.validate();
            return {"valid": True};
        } except ValueError as error {
            return {"valid": False, "error": str(error)};
        }
    }

    # --- macOS Policy & AppleScript ---
    if command == "mac-policy" {
        app: str = str(payload.get("app", ""));
        action: str = str(payload.get("action", ""));
        return {
            "valid": validate_mac_action(app, action),
            "policy": classify_mac_action(app, action).to_dict(),
        };
    }
    if command == "mac-script" {
        return {
            "script": build_applescript(
                str(payload.get("app", "")),
                str(payload.get("action", "")),
                payload.get("params", {}) as dict,
            )
        };
    }
    if command == "mac-validate-script" {
        return {
            "safe": validate_restricted_applescript(
                str(payload.get("script", ""))
            )
        };
    }

    # --- MCP Protocol ---
    if command == "mcp-initialize" {
        return initialize_request(str(payload.get("clientVersion", "1.0.0"))).to_dict();
    }
    if command == "mcp-tools-list" {
        return tools_list_request().to_dict();
    }
    if command == "mcp-call" {
        print(f"[Swirl][Jac] MCP tool call: {payload.get('toolName', '')}");
        return tool_call_request(
            str(payload.get("toolName", "")),
            payload.get("arguments", {}) as dict,
        ).to_dict();
    }
    if command == "mcp-validate" {
        return {"valid": validate_transport(payload)};
    }
    if command == "mcp-validate-name" {
        return {"valid": validate_server_name(str(payload.get("name", "")))};
    }
    if command == "mcp-validate-args" {
        errors = validate_tool_arguments(
            payload.get("schema", {}) as dict,
            payload.get("arguments", {}) as dict,
        );
        return {"valid": len(errors) == 0, "errors": errors};
    }
    if command == "mcp-parse-tools" {
        tools = parse_tools_response(payload);
        return {"tools": [t.to_dict() for t in tools]};
    }
    if command == "mcp-notifications-init" {
        return notifications_initialized_request().to_dict();
    }
    if command == "mcp-resources-list" {
        return resources_list_request().to_dict();
    }
    if command == "mcp-prompts-list" {
        return prompts_list_request().to_dict();
    }
    if command == "mcp-servers" {
        return {"servers": builtin_mcp_servers()};
    }
    if command == "mcp-server-config" {
        return builtin_mcp_server(str(payload.get("name", "")));
    }

    # --- Storage ---
    if command == "save-workflow" {
        record = save_workflow(
            str(payload.get("name", "")),
            payload.get("workflow", {}) as dict,
        );
        return record.to_dict();
    }
    if command == "load-workflow" {
        record = load_workflow(str(payload.get("name", "")));
        return record.to_dict();
    }
    if command == "list-workflows" {
        records = list_workflows();
        return {"workflows": [r.to_dict() for r in records]};
    }
    if command == "delete-workflow" {
        return {"deleted": delete_workflow(str(payload.get("name", "")))};
    }
    if command == "save-trace" {
        filename = save_trace(payload.get("trace", {}) as dict);
        return {"filename": filename};
    }

    # --- Block Definitions ---
    if command == "block-categories" {
        return {"categories": [c.to_dict() for c in BLOCK_CATEGORIES()]};
    }
    if command == "block-library" {
        return {"blocks": [b.to_dict() for b in BLOCK_LIBRARY()]};
    }
    if command == "block-by-type" {
        block = get_block_by_type(str(payload.get("type", "")));
        return {"block": block.to_dict() if block is not None else None};
    }
    if command == "blocks-by-category" {
        blocks = get_blocks_by_category(str(payload.get("category", "")));
        return {"blocks": [b.to_dict() for b in blocks]};
    }
    if command == "workflow-presets" {
        presets = workflow_presets();
        return {"presets": [p.to_dict() for p in presets]};
    }
    if command == "default-workflow" {
        return default_starter_workflow();
    }
    if command == "category-color" {
        return {"color": category_color(str(payload.get("category", "")))};
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
