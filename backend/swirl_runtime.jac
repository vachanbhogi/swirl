"""Command-line adapter used by Swirl's Tauri native process."""

import json;
import sys;
import from backend.workflow_agent {
    PromptToWorkflowWalker, generate_app_tool, is_app_tool_prompt,
    plan_workflow, transform_text
}
import from backend.code_generator { JacCodeGeneratorWalker }
import from backend.mac_control { classify_mac_action, validate_mac_action }
import from backend.models {
    validate_workflow, validate_generated_workflow
}
import from backend.storage {
    save_workflow, create_workflow, load_workflow, list_workflows,
    delete_workflow, save_trace, create_app_tool, list_app_tools,
    load_app_tool, app_tool_version, publish_app_tool_version,
    archive_app_tool
}
import from backend.mcp_bridge {
    initialize_request, tools_list_request, tool_call_request,
    validate_transport, validate_server_name,
    notifications_initialized_request, resources_list_request,
    prompts_list_request, builtin_mcp_servers, builtin_mcp_server
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
    if command == "prompt" or command == "prompt-llm" {
        prompt: str = str(payload.get("prompt", ""));
        if not prompt.strip() {
            raise ValueError("Prompt cannot be empty");
        }
        prompt_result = root spawn PromptToWorkflowWalker(
            user_prompt=prompt,
            use_llm=command == "prompt-llm",
        );
        if prompt_result.generated is None {
            raise RuntimeError("Jac workflow walker returned no workflow");
        }
        workflow: dict = prompt_result.generated.to_dict();
        validate_generated_workflow(workflow);
        return workflow;
    }
    if command == "build-from-prompt" or command == "build_from_prompt" {
        prompt: str = str(payload.get("prompt", "")).strip();
        if not prompt {
            raise ValueError("Prompt cannot be empty");
        }
        if is_app_tool_prompt(prompt) {
            return {
                "kind": "app_tool",
                "draft": generate_app_tool(
                    prompt,
                    payload.get("installedApplications", []) as list,
                ),
            };
        }
        prompt_result = root spawn PromptToWorkflowWalker(
            user_prompt=prompt,
            use_llm=bool(payload.get("useLlm", True)),
        );
        if prompt_result.generated is None {
            raise RuntimeError("Jac workflow walker returned no workflow");
        }
        workflow: dict = prompt_result.generated.to_dict();
        validate_generated_workflow(workflow);
        return {"kind": "workflow", "workflow": workflow};
    }
    if command == "llm-transform" {
        return {
            "text": transform_text(
                str(payload.get("text", "")),
                str(payload.get("instruction", "Summarize concisely")),
            )
        };
    }
    if command == "generate-app-tool" or command == "generate_app_tool" {
        return {
            "draft": generate_app_tool(
                str(payload.get("prompt", "")),
                payload.get("installedApplications", []) as list,
            )
        };
    }
    if command == "convert-legacy-app-agent" {
        application: str = str(payload.get("application", "")).strip();
        legacy_prompt: str = str(payload.get("prompt", "")).strip();
        if not application or not legacy_prompt {
            raise ValueError(
                "Legacy conversion requires application and prompt"
            );
        }
        return {
            "draft": generate_app_tool(
                f"Make a tool for {application} that {legacy_prompt}",
                payload.get("installedApplications", []) as list,
            )
        };
    }
    if command == "tool-create" or command == "create-app-tool" {
        version_value: any = payload.get("version", payload.get("tool", {}));
        if not isinstance(version_value, dict) {
            raise ValueError("Tool creation requires a validated version object");
        }
        return {
            "record": create_app_tool(
                version_value as dict,
                str(payload.get("dataDir", "")),
            ).to_dict()
        };
    }
    if command == "tool-list" or command == "list-app-tools" {
        return {
            "records": [
                record.to_dict()
                for record in list_app_tools(
                    str(payload.get("dataDir", "")),
                    bool(payload.get("includeArchived", False)),
                )
            ]
        };
    }
    if command == "tool-load" or command == "load-app-tool" {
        record = load_app_tool(
            str(payload.get("id", payload.get("toolId", ""))),
            str(payload.get("dataDir", "")),
        );
        requested_version: int = int(payload.get("version", 0));
        return {
            "record": record.to_dict(),
            "version": app_tool_version(record, requested_version),
        };
    }
    if command == "tool-publish" or command == "publish-app-tool-version" {
        version_value: any = payload.get("version", payload.get("tool", {}));
        if not isinstance(version_value, dict) {
            raise ValueError("Tool publish requires a validated version object");
        }
        record = publish_app_tool_version(
            str(payload.get("id", payload.get("toolId", ""))),
            version_value as dict,
            str(payload.get("dataDir", "")),
        );
        return {
            "record": record.to_dict(),
            "version": app_tool_version(record),
        };
    }
    if command == "tool-archive" or command == "archive-app-tool" {
        return {
            "archived": archive_app_tool(
                str(payload.get("id", payload.get("toolId", ""))),
                str(payload.get("dataDir", "")),
            )
        };
    }
    if command == "plan" {
        validate_workflow(payload);
        return {"plan": plan_workflow(payload)};
    }
    if command == "code" {
        validate_workflow(payload);
        code_result = root spawn JacCodeGeneratorWalker(workflow=payload);
        return {"source": code_result.reports[0]};
    }
    if command == "validate" {
        return validate_workflow(payload);
    }
    if command == "validate-generated" {
        return validate_generated_workflow(payload);
    }
    if command == "storage-save" {
        return {
            "record": save_workflow(
                str(payload.get("name", "")),
                payload.get("workflow", {}) as dict,
                str(payload.get("dataDir", "")),
            ).to_dict()
        };
    }
    if command == "storage-create" {
        return {
            "record": create_workflow(
                str(payload.get("name", "")),
                payload.get("workflow", {}) as dict,
                str(payload.get("dataDir", "")),
            ).to_dict()
        };
    }
    if command == "storage-load" {
        return {
            "record": load_workflow(
                str(payload.get("name", "")),
                str(payload.get("dataDir", "")),
            ).to_dict()
        };
    }
    if command == "storage-list" {
        return {
            "records": [
                record.to_dict()
                for record in list_workflows(
                    str(payload.get("dataDir", ""))
                )
            ]
        };
    }
    if command == "storage-delete" {
        return {
            "deleted": delete_workflow(
                str(payload.get("name", "")),
                str(payload.get("dataDir", "")),
            )
        };
    }
    if command == "storage-trace" {
        return {
            "fileName": save_trace(
                payload.get("trace", {}) as dict,
                str(payload.get("dataDir", "")),
            )
        };
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
        return initialize_request(
            str(payload.get("clientVersion", "1.0.0"))
        ).to_dict();
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
    if command == "mcp-notifications-init" {
        return notifications_initialized_request();
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
    raise ValueError(f"Unknown Swirl runtime command: {command}");
}


with entry:__main__ {
    try {
        if len(sys.argv) != 3 {
            raise ValueError(
                "Usage: jac run backend/swirl_runtime.jac <command> <payload.json>"
            );
        }
        emit({
            "ok": True,
            "data": run_command(sys.argv[1], read_payload(sys.argv[2])),
        });
    } except Exception as error {
        emit({"ok": False, "error": str(error)});
        sys.exit(1);
    }
}
