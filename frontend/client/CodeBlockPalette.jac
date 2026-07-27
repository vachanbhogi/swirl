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
) -> JsxElement {
    has active_tab: str = "actions";

    def handle_drag_start(event: any, block: dict) {
        event.dataTransfer.setData(
            "application/swirl-block",
            JSON.stringify(block),  # jac:ignore[W2001,W6002]
        );
        event.dataTransfer.effectAllowed = "copy";
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
    );

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
                {for block in filtered_blocks {
                    icon_component = block_icon(str(block["category"]));
                    <div
                        key={str(block["type"])}
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
