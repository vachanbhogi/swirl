"""Drag-and-click palette for workflow block definitions."""

import from "lucide-react" {
    Plus,
    Zap,
    Play,
    Sparkles,
    Command,
    Plug,
    GitBranch,
    Send,
    ArrowRight,
    Activity,
    Archive,
    ChevronDown,
    ChevronUp,
    Pencil,
    RefreshCw,
    Wrench,
}
import from .ToolBuilderPanel { ToolBuilderPanel }
import from .data {
    generated_tool_id,
    generated_tool_name,
    generated_tool_palette_block,
    generated_tool_status,
    generated_tool_version,
    generated_tool_version_number,
}


def block_icon(category: str) -> any {
    if category == "ai" { return Sparkles; }
    if category == "mac" { return Command; }
    if category == "mcp" { return Plug; }
    if category == "logic" { return GitBranch; }
    if category == "output" { return Send; }
    return Zap;
}


def block_color(category: str) -> str {
    if category == "trigger" {
        return "bg-purple-950/60 border-purple-800/60 text-purple-300";
    }
    if category == "ai" {
        return "bg-amber-950/60 border-amber-800/60 text-amber-300";
    }
    if category == "mac" {
        return "bg-cyan-950/60 border-cyan-800/60 text-cyan-300";
    }
    if category == "mcp" {
        return "bg-emerald-950/60 border-emerald-800/60 text-emerald-300";
    }
    if category == "output" {
        return "bg-rose-950/60 border-rose-800/60 text-rose-300";
    }
    return "bg-indigo-950/60 border-indigo-800/60 text-indigo-300";
}


def:pub CodeBlockPalette(
    blocks: list[dict],
    on_add_block: Callable[[dict], None] | None = None,
    generated_tools: list[dict] = [],
    tool_builder_prompt: str = "",
    on_tool_builder_closed: Callable[[], any] | None = None,
    on_generated_tool_saved: Callable[[dict, bool], any] | None = None,
    on_edit_generated_tool: Callable[[dict], any] | None = None,
    on_regenerate_generated_tool: Callable[[dict], any] | None = None,
    on_archive_generated_tool: Callable[[dict], any] | None = None,
    on_check_generated_tool: Callable[[dict], any] | None = None,
) -> JsxElement {
    has active_tab: str = "actions";
    has show_tool_builder: bool = bool(tool_builder_prompt.strip());
    has builder_prompt: str = tool_builder_prompt;
    has editing_tool: dict | None = None;
    has builder_auto_generate: bool = False;
    has builder_revision: int = 0;
    has tool_checks: dict = {};
    has archive_pending_id: str = "";

    can with [tool_builder_prompt] entry {
        if tool_builder_prompt.strip() {
            active_tab = "actions";
            builder_prompt = tool_builder_prompt;
            editing_tool = None;
            builder_auto_generate = True;
            builder_revision += 1;
            show_tool_builder = True;
        }
    }

    def handle_drag_start(event: any, block: dict) {
        event.dataTransfer.setData(
            "application/swirl-block",
            JSON.stringify(block),  # jac:ignore[W2001,W6002]
        );
        event.dataTransfer.effectAllowed = "copy";
    }

    def close_tool_builder {
        show_tool_builder = False;
        builder_prompt = "";
        editing_tool = None;
        builder_auto_generate = False;
        if on_tool_builder_closed { on_tool_builder_closed(); }
    }

    def handle_tool_saved(record: dict, add_to_canvas: bool) {
        if on_generated_tool_saved {
            on_generated_tool_saved(record, add_to_canvas);
        }
        if add_to_canvas and on_add_block {
            on_add_block(generated_tool_palette_block(record));
        }
    }

    def open_tool_editor(tool: dict, regenerate: bool = False) {
        active_tab = "actions";
        editing_tool = tool;
        builder_auto_generate = regenerate;
        builder_revision += 1;
        builder_prompt = str(
            generated_tool_version(tool).get("sourcePrompt")
            or tool.get("sourcePrompt")
            or ""
        );
        show_tool_builder = True;
        if regenerate and on_regenerate_generated_tool {
            on_regenerate_generated_tool(tool);
        } elif not regenerate and on_edit_generated_tool {
            on_edit_generated_tool(tool);
        }
    }

    async def check_tool(tool: dict) -> None {
        if not on_check_generated_tool { return; }
        tool_id: str = generated_tool_id(tool);
        tool_checks = {
            **tool_checks,
            tool_id: {"status": "checking", "message": "Checking application access…"},
        };
        try {
            result = await on_check_generated_tool(tool);
            tool_checks = {**tool_checks, tool_id: result};
        } except Exception as error {
            tool_checks = {
                **tool_checks,
                tool_id: {"status": "error", "message": str(error)},
            };
        }
    }

    filtered_blocks: list[dict] = [
        block
        for block in blocks
        if (
            block["category"] == "trigger"
            if active_tab == "triggers"
            else block["category"] != "trigger" and block["category"] != "source"
        )
    ];
    trigger_count: int = len(
        [
            block
            for block in blocks
            if block["category"] == "trigger"
        ]
    );
    action_count: int = len(
        [
            block
            for block in blocks
            if block["category"] != "trigger" and block["category"] != "source"
        ]
    ) + len(generated_tools);

    return <aside className="w-80 h-full bg-zinc-950 border-r border-zinc-800 p-5 flex flex-col justify-between select-none shrink-0">
        <div className="flex flex-col h-full overflow-hidden">
            <div className="pb-3 border-b border-zinc-800 shrink-0">
                <div className="flex items-center justify-between">
                    <div>
                        <h3 className="text-xs uppercase tracking-wider font-semibold text-zinc-200 font-sans">
                            Building Blocks
                        </h3>
                        <p className="text-[11px] text-zinc-400 mt-0.5 font-sans">
                            Drag onto canvas to build workflow
                        </p>
                    </div>
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
                </div>

                <div className="grid grid-cols-2 gap-1.5 p-1 mt-3.5 bg-zinc-900 border border-zinc-800 rounded-xl">
                    <button
                        onClick={lambda { active_tab = "triggers"; }}
                        className={
                            "flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-xs font-semibold transition font-sans "
                            + (
                                "bg-zinc-800 text-purple-300 border border-zinc-700 shadow-sm"
                                if active_tab == "triggers"
                                else "text-zinc-400 hover:text-zinc-200"
                            )
                        }
                    >
                        <Zap className="w-3.5 h-3.5 text-purple-400" />
                        <span>Triggers</span>
                        <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-zinc-950 text-zinc-400 font-mono">
                            {trigger_count}
                        </span>
                    </button>
                    <button
                        onClick={lambda { active_tab = "actions"; }}
                        className={
                            "flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-xs font-semibold transition font-sans "
                            + (
                                "bg-zinc-800 text-amber-300 border border-zinc-700 shadow-sm"
                                if active_tab == "actions"
                                else "text-zinc-400 hover:text-zinc-200"
                            )
                        }
                    >
                        <Play className="w-3.5 h-3.5 text-amber-400" />
                        <span>Actions</span>
                        <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-zinc-950 text-zinc-400 font-mono">
                            {action_count}
                        </span>
                    </button>
                </div>
            </div>

            <div className="py-2.5 px-1 shrink-0">
                <p className="text-[11px] text-zinc-400 font-sans">{
                    "⚡ What starts your automation:"
                    if active_tab == "triggers"
                    else "🚀 What your agent will execute:"
                }</p>
            </div>

            <div className="space-y-2.5 overflow-y-auto flex-1 pr-1 pb-2">
                {if active_tab == "actions" {
                    <div className="rounded-xl bg-cyan-950/25 border border-cyan-800/60 overflow-hidden">
                        <button
                            type="button"
                            onClick={lambda {
                                show_tool_builder = not show_tool_builder;
                                if not show_tool_builder {
                                    builder_prompt = "";
                                    editing_tool = None;
                                    builder_auto_generate = False;
                                }
                            }}
                            aria-expanded={show_tool_builder}
                            aria-controls="swirl-tool-builder"
                            className="w-full p-3 flex items-center justify-between gap-3 text-left hover:bg-cyan-950/35 transition"
                        >
                            <div className="flex items-center gap-3 min-w-0">
                                <div className="p-2 rounded-lg border bg-cyan-950/60 border-cyan-800/60 text-cyan-300 shrink-0">
                                    <Wrench className="w-4 h-4" aria-hidden="true" />
                                </div>
                                <div className="min-w-0">
                                    <h4 className="text-xs font-semibold text-cyan-100 font-sans">
                                        Make a tool
                                    </h4>
                                    <p className="text-[10px] text-cyan-300/70 truncate font-sans">
                                        Describe it. Swirl builds it.
                                    </p>
                                </div>
                            </div>
                            {if show_tool_builder {
                                <ChevronUp className="w-4 h-4 text-cyan-400 shrink-0" aria-hidden="true" />
                            } else {
                                <ChevronDown className="w-4 h-4 text-cyan-400 shrink-0" aria-hidden="true" />
                            }}
                        </button>

                        {if show_tool_builder {
                            <div id="swirl-tool-builder" className="px-3 pb-3 pt-2 border-t border-cyan-900/70">
                                <ToolBuilderPanel
                                    key={
                                        "tool-builder-"
                                        + generated_tool_id(editing_tool or {})
                                        + "-"
                                        + builder_prompt
                                        + "-"
                                        + str(builder_revision)
                                    }
                                    initial_prompt={builder_prompt}
                                    existing_tool={editing_tool}
                                    auto_generate={builder_auto_generate}
                                    on_saved={handle_tool_saved}
                                    on_close={close_tool_builder}
                                    compact={True}
                                />
                            </div>
                        }}
                    </div>
                }}

                {if active_tab == "actions" {
                    <section aria-labelledby="my-tools-heading" className="pt-1 space-y-2">
                        <div className="flex items-center justify-between px-1">
                            <h4 id="my-tools-heading" className="text-[11px] font-semibold text-zinc-300">
                                My Tools
                            </h4>
                            <span className="text-[10px] font-mono text-zinc-500">
                                {len(generated_tools)}
                            </span>
                        </div>
                        {if not generated_tools {
                            <div className="rounded-xl border border-dashed border-zinc-700 bg-zinc-900/40 px-3 py-3 text-[11px] leading-relaxed text-zinc-400">
                                Your generated tools will stay here across projects. Start with “Make a tool to text a friend on Discord.”
                            </div>
                        }}
                        {for tool in generated_tools {
                            palette_block: dict = generated_tool_palette_block(tool);
                            tool_id: str = generated_tool_id(tool);
                            tool_status: str = generated_tool_status(tool);
                            check_result: dict = (
                                tool_checks.get(tool_id) as dict
                                if isinstance(tool_checks.get(tool_id), dict)
                                else {}
                            );
                            displayed_status: str = str(
                                check_result.get("status")
                                or check_result.get("state")
                                or tool_status
                                or "untested"
                            ).lower();
                            <article
                                key={str(palette_block["paletteId"])}
                                draggable={True}
                                onDragStart={lambda (event: Event) {
                                    handle_drag_start(event, palette_block);
                                }}
                                className="group rounded-xl bg-zinc-900 border border-zinc-800 hover:border-cyan-800/80 transition-colors p-3 cursor-grab active:cursor-grabbing"
                            >
                                <div className="flex items-start gap-2.5">
                                    <div className="w-8 h-8 rounded-lg bg-cyan-950 border border-cyan-800 text-cyan-300 flex items-center justify-center shrink-0">
                                        <Wrench className="w-3.5 h-3.5" aria-hidden="true" />
                                    </div>
                                    <div className="min-w-0 flex-1">
                                        <div className="flex items-start justify-between gap-2">
                                            <h5 className="text-xs font-semibold text-zinc-100 truncate">
                                                {generated_tool_name(tool)}
                                            </h5>
                                            <span className={
                                                "rounded-full px-1.5 py-0.5 text-[9px] font-semibold capitalize shrink-0 "
                                                + (
                                                    "bg-emerald-950 text-emerald-300"
                                                    if displayed_status in ["ready", "passed", "available"]
                                                    else (
                                                        "bg-rose-950 text-rose-300"
                                                        if displayed_status in ["error", "unavailable", "failed"]
                                                        else "bg-amber-950 text-amber-300"
                                                    )
                                                )
                                            }>
                                                {displayed_status.replace("_", " ")}
                                            </span>
                                        </div>
                                        <p className="mt-0.5 text-[10px] leading-relaxed text-zinc-400 line-clamp-2">
                                            {palette_block["description"]}
                                        </p>
                                        <p className="mt-1 text-[9px] font-mono text-zinc-500">
                                            pinned v{generated_tool_version_number(tool)}
                                        </p>
                                    </div>
                                </div>
                                {if check_result.get("message") {
                                    <p role="status" className="mt-2 text-[10px] leading-relaxed text-zinc-400">
                                        {check_result["message"]}
                                    </p>
                                }}
                                <div className="mt-2.5 pt-2 border-t border-zinc-800 flex items-center gap-1">
                                    <button
                                        type="button"
                                        onClick={lambda {
                                            if on_add_block { on_add_block(palette_block); }
                                        }}
                                        aria-label={"Add " + generated_tool_name(tool) + " to canvas"}
                                        title="Add to canvas"
                                        className="flex-1 min-h-8 inline-flex items-center justify-center gap-1 rounded-lg bg-cyan-700 hover:bg-cyan-600 text-[10px] font-semibold text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
                                    >
                                        <Plus className="w-3 h-3" aria-hidden="true" />
                                        Add
                                    </button>
                                    <button
                                        type="button"
                                        onClick={lambda { open_tool_editor(tool); }}
                                        aria-label={"Edit " + generated_tool_name(tool)}
                                        title="Edit"
                                        className="min-w-8 min-h-8 inline-flex items-center justify-center rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                                    >
                                        <Pencil className="w-3.5 h-3.5" aria-hidden="true" />
                                    </button>
                                    <button
                                        type="button"
                                        onClick={lambda { open_tool_editor(tool, True); }}
                                        aria-label={"Regenerate " + generated_tool_name(tool)}
                                        title="Regenerate"
                                        className="min-w-8 min-h-8 inline-flex items-center justify-center rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                                    >
                                        <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
                                    </button>
                                    <button
                                        type="button"
                                        disabled={not on_check_generated_tool or displayed_status == "checking"}
                                        onClick={lambda { check_tool(tool); }}
                                        aria-label={"Check " + generated_tool_name(tool)}
                                        title="Check application access"
                                        className="min-w-8 min-h-8 inline-flex items-center justify-center rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 disabled:opacity-40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                                    >
                                        <Activity className={"w-3.5 h-3.5 " + ("animate-pulse" if displayed_status == "checking" else "")} aria-hidden="true" />
                                    </button>
                                    <button
                                        type="button"
                                        disabled={not on_archive_generated_tool}
                                        onClick={lambda {
                                            if archive_pending_id == tool_id and on_archive_generated_tool {
                                                on_archive_generated_tool(tool);
                                                archive_pending_id = "";
                                            } else {
                                                archive_pending_id = tool_id;
                                            }
                                        }}
                                        aria-label={
                                            ("Confirm archive " if archive_pending_id == tool_id else "Archive ")
                                            + generated_tool_name(tool)
                                        }
                                        title={"Confirm archive" if archive_pending_id == tool_id else "Archive"}
                                        className={
                                            "min-h-8 inline-flex items-center justify-center gap-1 rounded-lg disabled:opacity-40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400 "
                                            + (
                                                "px-2 bg-rose-950/60 text-rose-200"
                                                if archive_pending_id == tool_id
                                                else "min-w-8 text-zinc-500 hover:text-rose-300 hover:bg-rose-950/40"
                                            )
                                        }
                                    >
                                        <Archive className="w-3.5 h-3.5" aria-hidden="true" />
                                        {if archive_pending_id == tool_id {
                                            <span className="text-[9px] font-semibold">Confirm</span>
                                        }}
                                    </button>
                                </div>
                            </article>
                        }}
                    </section>
                }}

                {for block in filtered_blocks {
                    icon_component = block_icon(str(block["category"]));
                    <div
                        key={str(block.get("paletteId") or block["type"])}
                        draggable={True}
                        onDragStart={lambda (event: Event) {
                            handle_drag_start(event, block);
                        }}
                        className="group p-3 rounded-2xl bg-zinc-900 border border-zinc-800/80 hover:border-zinc-700 transition cursor-grab active:cursor-grabbing flex items-center justify-between shadow-sm"
                    >
                        <div className="flex items-center gap-3 overflow-hidden">
                            <div className={
                                "p-2 rounded-xl border shrink-0 "
                                + block_color(str(block["category"]))
                            }>
                                <@icon_component className="w-4 h-4" />
                            </div>
                            <div className="overflow-hidden">
                                <h4 className="text-xs font-semibold text-zinc-100 group-hover:text-white transition truncate font-sans">
                                    {block["title"]}
                                </h4>
                                <p className="text-[10px] text-zinc-400 line-clamp-1 font-sans">
                                    {block["description"]}
                                </p>
                            </div>
                        </div>
                        <button
                            onClick={lambda {
                                if on_add_block { on_add_block(block); }
                            }}
                            className="p-1.5 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition shrink-0 ml-2"
                            title="Add Block to Canvas"
                        >
                            <Plus className="w-4 h-4" />
                        </button>
                    </div>
                }}
            </div>

            <div className="pt-3 border-t border-zinc-800 shrink-0">
                <div className="p-2.5 rounded-2xl bg-zinc-900/60 border border-zinc-800 flex items-center gap-2 text-zinc-400">
                    <ArrowRight className="w-3.5 h-3.5 text-zinc-400 shrink-0" />
                    <p className="text-[11px] text-zinc-400 leading-snug font-sans">
                        Drag any block onto the canvas to connect steps!
                    </p>
                </div>
            </div>
        </div>
    </aside>;
}
