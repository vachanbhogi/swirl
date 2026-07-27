"""Block inspector and source/action configuration editor."""

import from "lucide-react" {
    X,
    Settings,
    Trash2,
    CheckCircle2,
    HelpCircle,
    Play,
    Copy,
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

    is_source: bool = selected_node["category"] == "source";
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
        if not is_source or item[0] != "eventType"
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

            {if not is_source {
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

            {if is_source {
                <div>
                    <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
                        Trigger Event Type
                    </label>
                    <select
                        value={config["eventType"] or "trigger_email"}
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

            <div className="space-y-4 pt-2">
                <div className="flex items-center justify-between text-[11px] font-bold text-zinc-400 uppercase tracking-wider">
                    <span>Configurable Settings</span>
                    <HelpCircle className="w-3.5 h-3.5 text-zinc-500" />
                </div>

                {for item in config_entries {
                    key: str = str(item[0]);
                    value = item[1];
                    label: str = (
                        FRIENDLY_KEY_LABELS[key]
                        if key in FRIENDLY_KEY_LABELS
                        else key
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
                                <option value="continuous">Continuous — re-arm until stopped</option>
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
