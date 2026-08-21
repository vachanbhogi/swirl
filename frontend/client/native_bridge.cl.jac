"""Typed client wrappers around Swirl's Tauri IPC commands."""

import from "@tauri-apps/api/core" { invoke }
import from "@tauri-apps/api/event" { listen }


def:pub is_tauri_environment -> bool {
    return bool(window["__TAURI_INTERNALS__"] or window["__TAURI__"]);  # jac:ignore[W2001,W6002]
}


async def invoke_backend(command: str, args: dict = {}) -> any {
    if not is_tauri_environment() {
        raise RuntimeError(
            "The Swirl backend is available when running the Tauri desktop app."
        );
    }
    return await invoke(command, args);
}


async def:pub compile_workflow_prompt(prompt: str, use_llm: bool = True) -> any {
    return await invoke_backend(
        "compile_prompt",
        {"prompt": prompt, "useLlm": use_llm},
    );
}


async def:pub build_from_prompt(prompt: str, use_llm: bool = True) -> any {
    return await invoke_backend(
        "build_from_prompt",
        {"prompt": prompt, "useLlm": use_llm},
    );
}


async def:pub generate_application_tool(
    prompt: str,
    tool_id: str = "",
) -> any {
    return await invoke_backend(
        "generate_app_tool",
        {"prompt": prompt},
    );
}


async def:pub create_generated_tool(draft: dict) -> any {
    return await invoke_backend("create_app_tool", {"draft": draft});
}


async def:pub list_generated_tools -> list {
    return await invoke_backend("list_app_tools") as list;
}


async def:pub load_generated_tool(
    tool_id: str,
    version: int | None = None,
) -> any {
    return await invoke_backend(
        "load_app_tool",
        {"toolId": tool_id, "version": version},
    );
}


async def:pub publish_generated_tool(
    tool_id: str,
    draft: dict,
) -> any {
    return await invoke_backend(
        "publish_app_tool_version",
        {"toolId": tool_id, "draft": draft},
    );
}


async def:pub archive_generated_tool(tool_id: str) -> bool {
    return await invoke_backend(
        "archive_app_tool",
        {"toolId": tool_id},
    ) as bool;
}


async def:pub check_generated_tool(
    tool_id: str,
    version: int | None = None,
) -> any {
    return await invoke_backend(
        "check_app_tool",
        {"toolId": tool_id, "version": version},
    );
}


async def:pub resolve_workflow_approval(request: dict) -> any {
    return await invoke_backend(
        "resolve_workflow_approval",
        {"request": request},
    );
}


async def:pub start_workflow(
    workflow: dict,
    context: dict = {},
    approvals: list = [],
) -> any {
    return await invoke_backend(
        "start_workflow",
        {
            "request": {
                **workflow,
                "context": context,
                "approvals": approvals,
            }
        },
    );
}


async def:pub stop_workflow(run_id: str) -> any {
    return await invoke_backend("stop_workflow", {"runId": run_id});
}


async def:pub generate_jac_source(workflow: dict) -> str {
    return await invoke_backend(
        "generate_jac_source",
        {"workflow": workflow},
    ) as str;
}


async def:pub save_workflow(name: str, workflow: dict) -> any {
    return await invoke_backend(
        "save_workflow",
        {"name": name, "workflow": workflow},
    );
}


async def:pub create_workflow(name: str, workflow: dict) -> any {
    return await invoke_backend(
        "create_workflow",
        {"name": name, "workflow": workflow},
    );
}


async def:pub load_workflow(name: str) -> any {
    return await invoke_backend("load_workflow", {"name": name});
}


async def:pub list_workflows -> list {
    return await invoke_backend("list_workflows") as list;
}


async def:pub delete_workflow(name: str) -> bool {
    return await invoke_backend("delete_workflow", {"name": name}) as bool;
}


def:pub listen_to_workflow_events(handler: Callable[[any], None]) -> any {
    if not is_tauri_environment() {
        promise_factory: any = Promise;
        return promise_factory.resolve(lambda {});
    }
    return listen(
        "swirl-workflow-event",
        lambda (event: any) {
            handler(event.payload);
        },
    );
}
