"""Block inspector and source/action configuration editor."""

import from "lucide-react" {
    X,
    Settings,
    Trash2,
    CheckCircle2,
    HelpCircle,
    Play,
    Copy,
    AppWindow,
    Pin,
    RefreshCw,
    ShieldCheck,
}
import from .data {
    generated_tool_id,
    generated_tool_inputs,
    generated_tool_name,
    generated_tool_status,
    generated_tool_version_number,
}

glob CATEGORY_BG_MAP: dict[str, str] = {
    "source": "bg-orange-500/10 border-orange-500/30 text-orange-400",
    "ai": "bg-amber-500/10 border-amber-500/30 text-amber-400",
    "mac": "bg-cyan-500/10 border-cyan-500/30 text-cyan-400",
    "mcp": "bg-emerald-500/10 border-emerald-500/30 text-emerald-400",
    "output": "bg-rose-500/10 border-rose-500/30 text-rose-400",
};

glob FRIENDLY_KEY_LABELS: dict[str, str] = {
    "mailbox": "📥 Target Mailbox",
    "filterSubject": "🔍 Filter Subject (optional)",
    "checkIntervalSec": "⏱️ Check Every (seconds)",
    "waitTimeoutSec": "⌛ Stop Waiting After (seconds, 0 = never)",
    "runMode": "🔁 Run Mode",
    "cron": "📅 Schedule Pattern (Cron)",
    "timezone": "🌐 Timezone",
    "wakeWord": "🎙️ Voice Wake Word",
    "language": "🗣️ Recognition Language",
    "listenTimeoutSec": "⌛ Whisper Poll Timeout (seconds)",
    "phoneNumber": "📱 Self-Text Phone Number",
    "prompt": "✨ AI Assistant Instructions",
    "maxTokens": "📏 Response Detail Level",
    "temperature": "🎨 AI Creativity (0 = Precise, 1 = Creative)",
    "app": "💻 macOS Application",
    "action": "⚡ Action to Perform",
    "folder": "📁 Target Folder",
    "defaultTitle": "📝 Note Title",
    "targetDirectory": "📂 Destination Directory",
    "command": "💻 Terminal Command",
    "server": "🔌 MCP Server Name",
    "tool_name": "🛠️ Tool Function Name",
    "application": "🖥️ Application",
    "channel": "💬 Slack Channel",
    "webhookUrl": "🔗 Webhook URL",
    "watchPath": "📂 Watched Directory",
    "filePattern": "📄 File Pattern",
    "host": "🌐 Listener Host",
    "port": "🔌 Listener Port",
    "path": "↪ Webhook Path",
    "method": "HTTP Method",
    "authRequired": "🔒 Require Bearer Token",
    "authToken": "🔑 Bearer Token",
    "watchText": "📋 Watch Text",
    "minChars": "Minimum Characters",
};


def category_for(category_id: str, block_categories: list[dict]) -> dict {
    for category in block_categories {
        if category["id"] == category_id { return category; }
    }
    return block_categories[0];
}


def:pub NodePropertiesPanel(
    block_categories: list[dict],
    source_events: dict[str, dict],
    change_source_event_handler: Callable[[str, dict], dict],
    selected_node: dict,
    on_save_node_config: Callable[[str, str, dict, str | None], any],
    on_delete_node: Callable[[str], any],
    on_duplicate_node: Callable[[dict], any] | None,
    on_close: Callable[[], any],
    total_nodes: int,
    total_edges: int,
    on_run_workflow: Callable[[], any],
    available_tool_updates: dict = {},
    on_update_tool_version: Callable[[str, dict], any] | None = None,
    on_convert_legacy_app_agent: Callable[[dict], any] | None = None,
) -> JsxElement {
    has config: dict = {};
    has title: str = "";
    has custom_prompt: str = "";

    can with [selected_node] entry {
        config = selected_node["config"] as dict if selected_node["config"] else {};
        title = str(selected_node["title"] or "");
        custom_prompt = str(selected_node["customPrompt"] or "");
    }

    def save_field(key: str, value: any) {
        updated: dict = {**config, key: value};
        config = updated;
        on_save_node_config(
            str(selected_node["id"]),
            title,
            updated,
            custom_prompt,
        );
    }

    def save_title(value: str) {
        title = value;
        on_save_node_config(
            str(selected_node["id"]),
            value,
            config,
            custom_prompt,
        );
    }

    def save_custom_prompt(value: str) {
        custom_prompt = value;
        on_save_node_config(
            str(selected_node["id"]),
            title,
            config,
            value,
        );
    }

    def save_source_event(event_type: str) {
        updated: dict = change_source_event_handler(event_type, config);
        config = updated;
        on_save_node_config(
            str(selected_node["id"]),
            title,
            updated,
            custom_prompt,
        );
    }

    def save_binding(key: str, value: any, kind: str = "literal") {
        current_bindings: dict = (
            config.get("bindings") as dict
            if isinstance(config.get("bindings"), dict)
            else {}
        );
        updated: dict = {
            **config,
            "bindings": {
                **current_bindings,
                key: (
                    {"kind": "context", "path": str(value)}
                    if kind == "context"
                    else {"kind": "literal", "value": value}
                ),
            },
        };
        config = updated;
        on_save_node_config(
            str(selected_node["id"]),
            title,
            updated,
            custom_prompt,
        );
    }

    is_source: bool = selected_node["category"] == "source";
    is_app_agent: bool = selected_node["type"] == "mac_app_agent";
    is_generated_tool: bool = selected_node["type"] == "generated_app_tool";
    tool_snapshot: dict = (
        selected_node.get("toolSnapshot") as dict
        if isinstance(selected_node.get("toolSnapshot"), dict)
        else {}
    );
    tool_ref: dict = (
        selected_node.get("toolRef") as dict
        if isinstance(selected_node.get("toolRef"), dict)
        else {}
    );
    tool_id: str = str(tool_ref.get("id") or generated_tool_id(tool_snapshot));
    pinned_version: int = int(
        tool_ref.get("version")
        or generated_tool_version_number(tool_snapshot)
        or 1
    );
    pinned_tool_name: str = generated_tool_name(tool_snapshot);
    if pinned_tool_name == "Untitled Tool" {
        pinned_tool_name = str(selected_node.get("title", "Generated Tool"));
    }
    update_candidate: dict = (
        available_tool_updates.get(tool_id) as dict
        if tool_id and isinstance(available_tool_updates.get(tool_id), dict)
        else {}
    );
    update_version: int = (
        generated_tool_version_number(update_candidate)
        if update_candidate
        else pinned_version
    );
    tool_inputs: list[dict] = generated_tool_inputs(tool_snapshot);
    bindings: dict = (
        config.get("bindings") as dict
        if isinstance(config.get("bindings"), dict)
        else {}
    );
    category: dict = category_for(
        str(selected_node["category"]),
        block_categories,
    );
    category_class: str = (
        CATEGORY_BG_MAP[str(selected_node["category"])]
        if str(selected_node["category"]) in CATEGORY_BG_MAP
        else CATEGORY_BG_MAP["ai"]
    );
    config_entries: list[list] = [
        item
        for item in (Object.entries(config) as list[list])  # jac:ignore[W2001,W6002]
        if (not is_source or item[0] != "eventType")
            and (not is_generated_tool or item[0] != "bindings")
    ];
    source_event_entries: list[list] = (
        Object.entries(source_events) as list[list]
    );  # jac:ignore[W2001,W6002]

    return <aside className="w-80 h-full bg-zinc-950 border-l border-zinc-800 p-5 flex flex-col justify-between overflow-y-auto select-none shrink-0 animate-slide-up">
        <div className="space-y-5">
            <div className="pb-3 border-b border-zinc-800 flex items-center justify-between">
                <div className="flex items-center gap-2.5 overflow-hidden">
                    <div className={"p-2 rounded-xl border shrink-0 " + category_class}>
                        <Settings className="w-4 h-4" />
                    </div>
                    <div className="overflow-hidden">
                        <h3 className="font-bold text-white text-xs truncate font-sans">
                            Block Inspector
                        </h3>
                        <p className="text-[10px] text-zinc-400 font-sans truncate">
                            {category["name"]}
                        </p>
                    </div>
                </div>
                <button
                    onClick={lambda { on_close(); }}
                    className="p-1.5 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
                >
                    <X className="w-4 h-4" />
                </button>
            </div>

            <div>
                <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
                    Block Title
                </label>
                <input
                    type="text"
                    value={title}
                    onChange={lambda (event: ChangeEvent) {
                        save_title(event.target.value);
                    }}
                    className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-700 transition font-sans"
                />
            </div>

            {if not is_source and not is_app_agent and not is_generated_tool {
                <div>
                    <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
                        Custom Prompt
                    </label>
                    <textarea
                        rows={3}
                        value={custom_prompt}
                        onChange={lambda (event: ChangeEvent) {
                            save_custom_prompt(event.target.value);
                        }}
                        placeholder="Optional instructions for this block during execution"
                        className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-sans text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:border-zinc-700 transition resize-y"
                    />
                    <p className="mt-1 text-[10px] text-zinc-500">
                        AI blocks use this as their instruction. Other blocks receive it in execution context.
                    </p>
                </div>
            }}

            {if is_app_agent {
                <div className="rounded-xl bg-amber-950/30 border border-amber-800/70 p-3 space-y-2.5">
                    <div className="flex items-start gap-2">
                        <ShieldCheck className="w-4 h-4 mt-0.5 text-amber-300 shrink-0" aria-hidden="true" />
                        <div>
                            <p className="text-xs font-semibold text-amber-100">Legacy App Agent</p>
                            <p className="mt-1 text-[10px] leading-relaxed text-amber-200/75">
                                Convert this block to a reusable, versioned tool before running it. Its old generated script is never saved or trusted.
                            </p>
                        </div>
                    </div>
                    <button
                        type="button"
                        disabled={not on_convert_legacy_app_agent}
                        onClick={lambda {
                            if on_convert_legacy_app_agent {
                                on_convert_legacy_app_agent(selected_node);
                            }
                        }}
                        className="w-full flex items-center justify-center gap-1.5 rounded-lg bg-amber-700 hover:bg-amber-600 px-3 py-2 text-[11px] font-semibold text-white disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-300"
                    >
                        <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
                        Convert to My Tools
                    </button>
                </div>
            }}

            {if is_generated_tool {
                <div className="space-y-3">
                    <div className="rounded-xl bg-cyan-950/25 border border-cyan-900/80 p-3">
                        <div className="flex items-start gap-2.5">
                            <AppWindow className="w-4 h-4 mt-0.5 text-cyan-300 shrink-0" aria-hidden="true" />
                            <div className="min-w-0 flex-1">
                                <p className="text-xs font-semibold text-cyan-100 truncate">
                                    {pinned_tool_name}
                                </p>
                                <div className="mt-1 flex items-center gap-2 text-[10px] text-cyan-300/75">
                                    <span className="inline-flex items-center gap-1">
                                        <Pin className="w-3 h-3" aria-hidden="true" />
                                        Pinned v{pinned_version}
                                    </span>
                                    <span aria-hidden="true">·</span>
                                    <span className="capitalize">
                                        {generated_tool_status(tool_snapshot).replace("_", " ")}
                                    </span>
                                </div>
                            </div>
                        </div>
                        {if update_candidate and update_version > pinned_version {
                            <button
                                type="button"
                                onClick={lambda {
                                    if on_update_tool_version {
                                        on_update_tool_version(
                                            str(selected_node["id"]),
                                            update_candidate,
                                        );
                                    }
                                }}
                                disabled={not on_update_tool_version}
                                className="mt-3 w-full flex items-center justify-center gap-1.5 rounded-lg bg-cyan-700 hover:bg-cyan-600 px-3 py-2 text-[11px] font-semibold text-white disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
                            >
                                <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
                                Update to v{update_version}
                            </button>
                        }}
                    </div>

                    <div className="space-y-3">
                        <div className="flex items-center justify-between">
                            <p className="text-[11px] font-bold text-zinc-300 uppercase tracking-wider">
                                Tool inputs
                            </p>
                            <span className="text-[10px] text-zinc-500">
                                {len(tool_inputs)} field{"s" if len(tool_inputs) != 1 else ""}
                            </span>
                        </div>
                        {if tool_inputs {
                            <div className="space-y-3">
                                {for input_spec in tool_inputs {
                                    input_key: str = str(input_spec.get("key") or input_spec.get("name") or "input");
                                    input_type: str = str(
                                        input_spec.get("inputType")
                                        or input_spec.get("type")
                                        or "string"
                                    );
                                    raw_binding: any = bindings.get(input_key);
                                    binding_spec: dict = (
                                        raw_binding as dict
                                        if isinstance(raw_binding, dict)
                                        else {
                                            "kind": "literal",
                                            "value": (
                                                raw_binding
                                                if raw_binding is not None
                                                else input_spec.get("defaultValue", input_spec.get("default", ""))
                                            ),
                                        }
                                    );
                                    binding_kind: str = str(binding_spec.get("kind") or "literal");
                                    input_value: any = (
                                        binding_spec.get("path", "text")
                                        if binding_kind == "context"
                                        else binding_spec.get(
                                            "value",
                                            input_spec.get("defaultValue", input_spec.get("default", "")),
                                        )
                                    );
                                    <label key={input_key} className="block space-y-1">
                                        <span className="text-[11px] font-medium text-zinc-300">
                                            {input_spec.get("label") or input_key}
                                            {if input_spec.get("required") {
                                                <span className="text-rose-300" aria-label="required"> *</span>
                                            }}
                                        </span>
                                        <select
                                            value={binding_kind}
                                            aria-label={"Value source for " + str(input_spec.get("label") or input_key)}
                                            onChange={lambda (event: ChangeEvent) {
                                                if event.target.value == "context" {
                                                    save_binding(input_key, "text", "context");
                                                } else {
                                                    save_binding(
                                                        input_key,
                                                        input_spec.get("defaultValue", input_spec.get("default", "")),
                                                    );
                                                }
                                            }}
                                            className="w-full rounded-lg bg-zinc-950 border border-zinc-800 px-2.5 py-1.5 text-[10px] font-semibold text-zinc-300 focus:outline-none focus:border-cyan-500"
                                        >
                                            <option value="literal">Fixed value</option>
                                            <option value="context">Previous step output</option>
                                        </select>
                                        {if binding_kind == "context" {
                                            <input
                                                type="text"
                                                value={input_value}
                                                placeholder="text"
                                                aria-label={"Workflow context path for " + str(input_spec.get("label") or input_key)}
                                                onChange={lambda (event: ChangeEvent) {
                                                    save_binding(input_key, event.target.value, "context");
                                                }}
                                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-xs font-mono text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:border-cyan-500"
                                            />
                                        } elif input_type == "boolean" {
                                            <button
                                                type="button"
                                                onClick={lambda {
                                                    save_binding(input_key, not bool(input_value));
                                                }}
                                                aria-pressed={bool(input_value)}
                                                className={
                                                    "w-full flex items-center justify-between rounded-lg border px-3 py-2 text-xs font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400 "
                                                    + (
                                                        "bg-cyan-950 border-cyan-800 text-cyan-100"
                                                        if bool(input_value)
                                                        else "bg-zinc-900 border-zinc-700 text-zinc-400"
                                                    )
                                                }
                                            >
                                                <span>{"Enabled" if bool(input_value) else "Disabled"}</span>
                                                <CheckCircle2 className="w-4 h-4" aria-hidden="true" />
                                            </button>
                                        } elif input_type in ["number", "integer"] {
                                            <input
                                                type="number"
                                                value={input_value}
                                                required={bool(input_spec.get("required"))}
                                                onChange={lambda (event: ChangeEvent) {
                                                    save_binding(input_key, float(event.target.value));
                                                }}
                                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-xs font-mono text-zinc-100 focus:outline-none focus:border-cyan-500"
                                            />
                                        } elif input_spec.get("sensitive") {
                                            <input
                                                type="password"
                                                value={input_value}
                                                required={bool(input_spec.get("required"))}
                                                autoComplete="off"
                                                onChange={lambda (event: ChangeEvent) {
                                                    save_binding(input_key, event.target.value);
                                                }}
                                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-xs text-zinc-100 focus:outline-none focus:border-cyan-500"
                                            />
                                        } else {
                                            <textarea
                                                rows={3 if input_type in ["multiline", "textarea"] else 1}
                                                value={input_value}
                                                required={bool(input_spec.get("required"))}
                                                placeholder={str(input_spec.get("placeholder") or "")}
                                                onChange={lambda (event: ChangeEvent) {
                                                    save_binding(input_key, event.target.value);
                                                }}
                                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-xs leading-relaxed text-zinc-100 placeholder:text-zinc-500 focus:outline-none focus:border-cyan-500 resize-y"
                                            />
                                        }}
                                        {if input_spec.get("description") {
                                            <span className="block text-[10px] leading-relaxed text-zinc-500">
                                                {input_spec["description"]}
                                            </span>
                                        }}
                                    </label>
                                }}
                            </div>
                        } else {
                            <div className="rounded-xl bg-zinc-900 border border-zinc-800 px-3 py-2.5 flex items-start gap-2 text-[11px] text-zinc-400">
                                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" aria-hidden="true" />
                                This tool has no configurable inputs.
                            </div>
                        }}
                    </div>
                </div>
            }}

            {if is_source {
                <div>
                    <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
                        Trigger Event Type
                    </label>
                    <select
                        value={config["eventType"] or "trigger_manual"}
                        onChange={lambda (event: ChangeEvent) {
                            save_source_event(event.target.value);
                        }}
                        className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-700 font-sans"
                    >
                        {for entry in source_event_entries {
                            event_type: str = str(entry[0]);
                            event_definition: dict = entry[1] as dict;
                            <option key={event_type} value={event_type}>
                                {event_definition["title"]}
                            </option>
                        }}
                    </select>
                </div>
            }}

            {if not is_generated_tool {
            <div className="space-y-4 pt-2">
                <div className="flex items-center justify-between text-[11px] font-bold text-zinc-400 uppercase tracking-wider">
                    <span>Configurable Settings</span>
                    <HelpCircle className="w-3.5 h-3.5 text-zinc-500" />
                </div>

                {for item in config_entries {
                    key: str = str(item[0]);
                    value = item[1];
                    label: str = (
                        "📝 Prompt"
                        if is_app_agent and key == "prompt"
                        else (
                            FRIENDLY_KEY_LABELS[key]
                            if key in FRIENDLY_KEY_LABELS
                            else key
                        )
                    );
                    is_number: bool = (
                        isinstance(value, int) or isinstance(value, float)
                    ) and not isinstance(value, bool);
                    <div key={key} className="space-y-1">
                        <label className="block text-[11px] font-medium text-zinc-300 font-sans">
                            {label}
                        </label>
                        {if is_source and key == "runMode" {
                            <select
                                value={value}
                                onChange={lambda (event: ChangeEvent) {
                                    save_field(key, event.target.value);
                                }}
                                className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-600"
                            >
                                <option value="once">Once — stop after one event</option>
                                <option
                                    value="continuous"
                                    disabled={config.get("eventType") == "trigger_manual"}
                                >
                                    Continuous — re-arm until stopped
                                </option>
                            </select>
                        } elif is_number and is_source {
                            <input
                                type="number"
                                min={"0" if key == "waitTimeoutSec" else "1"}
                                max={"65535" if key == "port" else ""}
                                value={value}
                                onChange={lambda (event: ChangeEvent) {
                                    save_field(key, int(event.target.value));
                                }}
                                className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-mono text-zinc-200 focus:outline-none focus:border-zinc-600"
                            />
                        } elif is_number {
                            <div className="flex items-center gap-2">
                                <input
                                    type="range"
                                    min={"0" if key == "temperature" else "1"}
                                    max={"1" if key == "temperature" else "3000"}
                                    step={"0.1" if key == "temperature" else "10"}
                                    value={value}
                                    onChange={lambda (event: ChangeEvent) {
                                        save_field(key, float(event.target.value));
                                    }}
                                    className="flex-1 accent-zinc-200"
                                />
                                <span className="text-xs font-mono font-bold text-white w-12 text-right">
                                    {str(value)}
                                </span>
                            </div>
                        } elif isinstance(value, bool) {
                            <button
                                type="button"
                                onClick={lambda { save_field(key, not value); }}
                                className={
                                    "w-full py-1.5 px-3 rounded-xl text-xs font-semibold border transition text-left flex items-center justify-between "
                                    + (
                                        "bg-zinc-800 border-zinc-700 text-white"
                                        if value
                                        else "bg-zinc-900 border-zinc-800 text-zinc-400"
                                    )
                                }
                            >
                                <span>{"Enabled" if value else "Disabled"}</span>
                                <CheckCircle2 className={
                                    "w-4 h-4 "
                                    + ("text-white" if value else "text-zinc-500")
                                } />
                            </button>
                        } else {
                            <textarea
                                rows={
                                    3
                                    if isinstance(value, str) and len(value) > 35
                                    else 1
                                }
                                value={value}
                                onChange={lambda (event: ChangeEvent) {
                                    save_field(key, event.target.value);
                                }}
                                className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-sans text-zinc-200 focus:outline-none focus:border-zinc-700 transition resize-none"
                            />
                        }}
                    </div>
                }}
            </div>
            }}
        </div>

        <div className="pt-4 border-t border-zinc-800 flex items-center justify-between gap-2">
            {if on_duplicate_node and not is_source {
                <button
                    onClick={lambda { on_duplicate_node(selected_node); }}
                    className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-semibold transition"
                >
                    <Copy className="w-3.5 h-3.5" />
                    <span>Duplicate</span>
                </button>
            }}
            {if not is_source {
                <button
                    onClick={lambda {
                        on_delete_node(str(selected_node["id"]));
                    }}
                    className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-rose-950/40 hover:bg-rose-900/60 text-rose-300 text-xs font-semibold transition border border-rose-800/50"
                    title="Remove block"
                >
                    <Trash2 className="w-3.5 h-3.5" />
                    <span>Delete</span>
                </button>
            }}
        </div>
    </aside>;
}
