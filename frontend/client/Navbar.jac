"""Top navigation and workflow run controls."""

import from "lucide-react" {
    Play,
    Layers,
    Sparkles,
    Square,
    Terminal,
    ArrowLeft,
    Loader2,
    CircleAlert,
}


def:pub SaveStatus(
    current_workflow_name: str | None,
    has_unsaved_changes: bool,
    is_saving: bool,
    save_error: str | None,
) -> JsxElement {
    if save_error {
        return <CircleAlert
            className="w-3.5 h-3.5 text-red-400 shrink-0"
            title={save_error}
        />;
    }
    if is_saving {
        return <Loader2 className="w-3 h-3 text-zinc-500 animate-spin shrink-0" />;
    }
    if has_unsaved_changes {
        return <span
            className="w-2 h-2 rounded-full bg-amber-400 shrink-0"
            title="Unsaved changes"
        />;
    }
    if current_workflow_name {
        return <span
            className="w-2 h-2 rounded-full bg-emerald-400 shrink-0"
            title="Saved"
        />;
    }
    return <span className="hidden" />;
}


def:pub Navbar(
    active_tab: str = "workflow",
    set_active_tab: Callable[[str], any] | None = None,
    on_run_workflow: Callable[[], any] | None = None,
    on_stop_workflow: Callable[[], any] | None = None,
    is_executing: bool = False,
    is_stopping: bool = False,
    active_run_mode: str | None = None,
    show_logs_inspector: bool = False,
    on_toggle_logs: Callable[[], any] | None = None,
    logs_count: int = 0,
    current_workflow_name: str | None = None,
    has_unsaved_changes: bool = False,
    is_saving: bool = False,
    save_error: str | None = None,
    show_back_button: bool = False,
    on_back: Callable[[], any] | None = None,
) -> JsxElement {
    display_name: str = current_workflow_name or "Untitled";

    def select_workflow(_event: MouseEvent) {
        if set_active_tab { set_active_tab("workflow"); }
    }

    def select_ai(_event: MouseEvent) {
        if set_active_tab { set_active_tab("ai"); }
    }

    def handle_back(_event: MouseEvent) {
        if on_back { on_back(); }
    }

    def toggle_logs(_event: MouseEvent) {
        if on_toggle_logs { on_toggle_logs(); }
    }

    def run_workflow(_event: MouseEvent) {
        if on_run_workflow { on_run_workflow(); }
    }

    def stop_workflow(_event: MouseEvent) {
        if on_stop_workflow { on_stop_workflow(); }
    }

    return <header className="h-14 w-full bg-[#0A0D14]/95 border-b border-zinc-800/80 px-6 flex items-center justify-between z-40 select-none shrink-0 font-sans">
        <div className="flex items-center gap-2 min-w-[160px] mt-5">
            {if show_back_button {
                <button
                    key="back"
                    onClick={handle_back}
                    className="flex items-center gap-1.5 px-2 py-1.5 rounded-xl text-xs font-semibold text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
                    title="Back to Workflows"
                >
                    <ArrowLeft className="w-4 h-4" />
                </button>
                <span
                    key="workflow-name"
                    className="text-xs font-semibold text-zinc-300 truncate max-w-[180px]"
                    title={current_workflow_name or "Unsaved workflow"}
                >{display_name}</span>
                <SaveStatus
                    key="save-status"
                    current_workflow_name={current_workflow_name}
                    has_unsaved_changes={has_unsaved_changes}
                    is_saving={is_saving}
                    save_error={save_error}
                />
            } else {
                <div key="back-placeholder" className="w-16" />
            }}
        </div>

        <div className="flex items-center gap-1 p-1 bg-zinc-900/90 rounded-2xl border border-zinc-800">
            <button
                onClick={select_workflow}
                className={
                    "flex items-center gap-1.5 px-4 py-1.5 rounded-xl text-xs font-semibold transition font-sans "
                    + (
                        "bg-zinc-800 text-white shadow-sm border border-zinc-700"
                        if active_tab == "workflow"
                        else "text-zinc-400 hover:text-zinc-200"
                    )
                }
            >
                <Layers className="w-3.5 h-3.5" />
                <span>Workflow</span>
            </button>
            <button
                onClick={select_ai}
                className={
                    "flex items-center gap-1.5 px-4 py-1.5 rounded-xl text-xs font-semibold transition font-sans "
                    + (
                        "bg-zinc-800 text-white shadow-sm border border-zinc-700"
                        if active_tab == "ai"
                        else "text-zinc-400 hover:text-zinc-200"
                    )
                }
            >
                <Sparkles className="w-3.5 h-3.5" />
                <span>AI Builder</span>
            </button>
        </div>

        <div className="flex items-center gap-3">
            <button
                onClick={toggle_logs}
                className={
                    "flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-mono font-semibold border transition "
                    + (
                        "bg-purple-950/80 text-purple-300 border-purple-700 shadow-sm"
                        if show_logs_inspector
                        else "bg-zinc-900 text-zinc-300 border-zinc-800 hover:text-white hover:border-zinc-700"
                    )
                }
                title="Toggle Walker Logs Inspector"
            >
                <Terminal className="w-3.5 h-3.5 text-purple-400" />
                <span>{"Logs (" + str(logs_count) + ")"}</span>
            </button>

            {if is_executing {
                <button
                    key="stop-workflow"
                    onClick={stop_workflow}
                    disabled={is_stopping}
                    className="flex items-center gap-2 px-4 py-1.5 rounded-xl text-xs font-bold transition font-sans bg-rose-950/60 text-rose-200 border border-rose-800/70 hover:bg-rose-900/60 disabled:cursor-wait disabled:opacity-60"
                >
                    <Square className="w-3.5 h-3.5 fill-current" />
                    <span>{
                        "Stopping…"
                        if is_stopping
                        else (
                            "Stop Listener"
                            if active_run_mode == "continuous"
                            else "Stop Workflow"
                        )
                    }</span>
                </button>
            } else {
                <button
                    key="run-workflow"
                    onClick={run_workflow}
                    className="flex items-center gap-2 px-4 py-1.5 rounded-xl text-xs font-bold transition font-sans bg-white text-zinc-900 hover:bg-zinc-200 shadow-sm active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
                >
                    <Play className="w-3.5 h-3.5 fill-current" />
                    <span>Run Workflow</span>
                </button>
            }}
        </div>
    </header>;
}
