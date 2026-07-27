"""Live walker logs, node state, and execution payload drawer."""

import from "lucide-react" {
    Terminal,
    Layers,
    CheckCircle2,
    RotateCcw,
    Sparkles,
    X,
}


def result_entries(value: any) -> list {
    if isinstance(value, dict) {
        return Object.entries(value) as list;  # jac:ignore[W2001,W6002]
    }
    return [];
}


def:pub ExecutionInspector(
    is_open: bool,
    on_close: Callable[[], any],
    logs: list[dict],
    active_node: dict | None,
    execution_results: dict,
    on_clear_logs: Callable[[], any],
) -> JsxElement {
    has active_tab: str = "logs";

    if not is_open {
        return <div className="hidden" />;
    }
    output_entries: list[list] = (
        Object.entries(execution_results or {}) as list[list]
    );  # jac:ignore[W2001,W6002]

    return <div className="absolute bottom-4 left-4 right-4 z-40 max-h-64 bg-slate-950/95 border border-slate-800 rounded-2xl shadow-2xl backdrop-blur-xl text-slate-100 flex flex-col overflow-hidden animate-slide-up">
        <div className="h-10 px-4 bg-slate-900/90 border-b border-slate-800 flex items-center justify-between font-mono text-xs select-none">
            <div className="flex items-center gap-3">
                <button
                    onClick={lambda { active_tab = "logs"; }}
                    className={
                        "flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition "
                        + (
                            "bg-purple-950/70 text-purple-300 font-bold border border-purple-800/50"
                            if active_tab == "logs"
                            else "text-slate-400 hover:text-slate-200"
                        )
                    }
                >
                    <Terminal className="w-3.5 h-3.5" />
                    <span>{"Walker Logs (" + str(len(logs)) + ")"}</span>
                </button>
                <button
                    onClick={lambda { active_tab = "node"; }}
                    className={
                        "flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition "
                        + (
                            "bg-cyan-950/70 text-cyan-300 font-bold border border-cyan-800/50"
                            if active_tab == "node"
                            else "text-slate-400 hover:text-slate-200"
                        )
                    }
                >
                    <Layers className="w-3.5 h-3.5" />
                    <span>Node Inspector</span>
                </button>
                <button
                    onClick={lambda { active_tab = "payload"; }}
                    className={
                        "flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition "
                        + (
                            "bg-emerald-950/70 text-emerald-300 font-bold border border-emerald-800/50"
                            if active_tab == "payload"
                            else "text-slate-400 hover:text-slate-200"
                        )
                    }
                >
                    <Sparkles className="w-3.5 h-3.5" />
                    <span>{"Agent Outputs (" + str(len(output_entries)) + ")"}</span>
                </button>
            </div>
            <div className="flex items-center gap-2">
                <button
                    onClick={lambda { on_clear_logs(); }}
                    className="p-1 rounded-md text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
                    title="Clear Logs"
                >
                    <RotateCcw className="w-3.5 h-3.5" />
                </button>
                <button
                    onClick={lambda { on_close(); }}
                    className="p-1 rounded-md text-slate-400 hover:text-rose-400 hover:bg-slate-800 transition"
                    title="Close Inspector"
                >
                    <X className="w-4 h-4" />
                </button>
            </div>
        </div>

        <div className="flex-1 overflow-y-auto p-3.5 bg-slate-950/90 font-mono text-xs">
            {if active_tab == "logs" {
                <div className="space-y-1.5">
                    {if len(logs) == 0 {
                        <div className="text-slate-500 italic py-3 text-center">
                            No execution logs yet. Click "Run" to begin Jac graph traversal.
                        </div>
                    } else {
                        for (index, log) in enumerate(logs) {
                            log_type: str = str(log["type"]);
                            <div
                                key={str(index)}
                                className="flex items-start gap-2 text-slate-300 hover:bg-white/5 p-1 rounded transition"
                            >
                                <span className="text-slate-500 shrink-0 text-[11px]">
                                    {"[" + str(log["time"]) + "]"}
                                </span>
                                <span className={
                                    "shrink-0 font-bold "
                                    + (
                                        "text-rose-400"
                                        if log_type == "error"
                                        else (
                                            "text-emerald-400"
                                            if log_type == "success"
                                            else "text-purple-400"
                                        )
                                    )
                                }>{log["prefix"]}</span>
                                <span className="text-slate-200 flex-1">{log["message"]}</span>
                            </div>
                        }
                    }}
                </div>
            }}

            {if active_tab == "node" {
                <div className="space-y-3">
                    {if active_node {
                        <div className="grid grid-cols-2 gap-4">
                            <div className="bg-slate-900/80 p-3 rounded-lg border border-slate-800">
                                <h4 className="font-bold text-purple-300 mb-1">
                                    {active_node["title"]}
                                </h4>
                                <p className="text-[11px] text-slate-400 mb-2">
                                    {"ID: " + str(active_node["id"]) + " | Category: " + str(active_node["category"])}
                                </p>
                                <div className="space-y-1 text-[11px]">
                                    <div>
                                        <strong className="text-slate-400">Jac Class:</strong>
                                        {" " + str(active_node["jacNode"] or "WorkflowBlock")}
                                    </div>
                                    <div>
                                        <strong className="text-slate-400">Status:</strong>
                                        <span className="text-emerald-400">
                                            {" " + str(active_node["status"] or "idle")}
                                        </span>
                                    </div>
                                </div>
                            </div>
                            <div className="bg-slate-900/80 p-3 rounded-lg border border-slate-800">
                                <h4 className="font-bold text-amber-300 mb-1">
                                    Configuration Parameters
                                </h4>
                                <pre className="text-[11px] text-amber-200 bg-slate-950 p-2 rounded overflow-x-auto">
                                    {JSON.stringify(active_node["config"], None, 2)}
                                </pre>
                            </div>
                        </div>
                    } else {
                        <div className="text-slate-500 italic py-3 text-center">
                            Select a node on the canvas to inspect its configuration and execution context.
                        </div>
                    }}
                </div>
            }}

            {if active_tab == "payload" {
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {if len(output_entries) == 0 {
                        <div className="text-slate-500 italic py-3 text-center col-span-2">
                            No execution results generated yet. Run the workflow to inspect output cards.
                        </div>
                    } else {
                        for output_entry in output_entries {
                            node_id: str = str(output_entry[0]);
                            result = output_entry[1];
                            entries: list[list] = result_entries(result) as list[list];
                            <div
                                key={node_id}
                                className="bg-slate-900/90 border border-emerald-500/30 p-3.5 rounded-xl shadow-lg"
                            >
                                <div className="flex items-center justify-between mb-2">
                                    <span className="flex items-center gap-1.5 font-bold text-emerald-300 text-xs">
                                        <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                                        {"Node Output (" + node_id + ")"}
                                    </span>
                                    <span className="text-[10px] bg-emerald-500/20 text-emerald-300 px-2 py-0.5 rounded border border-emerald-500/40">
                                        SUCCESS
                                    </span>
                                </div>
                                <div className="bg-slate-950 p-2.5 rounded-lg text-slate-200 text-xs font-mono space-y-1">
                                    {if len(entries) {
                                        for item in entries {
                                            <div key={str(item[0])}>
                                                <strong className="text-cyan-300">
                                                    {str(item[0]) + ":"}
                                                </strong>
                                                {" " + str(item[1])}
                                            </div>
                                        }
                                    } else {
                                        <div>{str(result)}</div>
                                    }}
                                </div>
                            </div>
                        }
                    }}
                </div>
            }}
        </div>
    </div>;
}
