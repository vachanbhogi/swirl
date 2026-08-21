"""Prompt-first workflow generation screen."""

import from "lucide-react" {
    AlertCircle,
    ArrowRight,
    CheckCircle2,
    Wand2,
    Loader2,
    Bot,
    Cpu,
    ArrowLeft,
    Wrench,
}
import from .data { is_tool_creation_intent }

glob PRESET_PROMPTS: list[dict] = [
    {
        "title": "Email & Notes Summarizer",
        "icon": "📧",
        "description": "Wait for incoming email, summarize key action items with Jac AI, and save a report in Apple Notes.",
        "prompt": "Whenever a new email arrives in my inbox, summarize its key points using AI, create a note in Apple Notes, and send a Mac notification.",
    },
    {
        "title": "File Organizer & MCP Extractor",
        "icon": "📁",
        "description": "Monitor Downloads for new documents, categorize files, and organize them into specific folders.",
        "prompt": "Watch my Downloads folder for new files, use MCP tool to categorize documents, move invoices to Invoices folder, and log results.",
    },
    {
        "title": "Daily Web Briefing",
        "icon": "⏰",
        "description": "Fetch a web page on a morning schedule, summarize it, and deliver a Mac notification.",
        "prompt": "Every day at 8:00 AM, fetch https://example.com with MCP, summarize the page using Jac AI, and send a Mac notification.",
    },
    {
        "title": "Discord Message Tool",
        "icon": "🛠️",
        "description": "Create a reusable action with Friend and Message inputs for Discord.",
        "prompt": "Make a tool to text a friend on Discord for me.",
    },
];


def:pub AIScreen(
    on_generate_from_prompt: Callable[[str], any],
    is_compiling_prompt: bool,
    on_switch_to_workflow: Callable[[], any],
    on_create_tool_from_prompt: Callable[[str], any] | None = None,
    compile_status: dict = {"type": "idle", "message": ""},
) -> JsxElement {
    has prompt_text: str = "";

    def handle_submit(event: FormEvent) {
        event.preventDefault();
        if prompt_text.strip() and not is_compiling_prompt {
            if is_tool_creation_intent(prompt_text) and on_create_tool_from_prompt {
                on_create_tool_from_prompt(prompt_text);
            } else {
                on_generate_from_prompt(prompt_text);
            }
        }
    }

    status_message: str = str(compile_status["message"] or "");
    status_type: str = str(compile_status["type"] or "idle");
    creates_tool: bool = bool(
        on_create_tool_from_prompt and is_tool_creation_intent(prompt_text)
    );

    return <div className="flex-1 w-full h-full bg-[#050508] text-white flex flex-col overflow-hidden font-sans select-none">
        <div className="flex-1 flex items-center justify-center p-8 overflow-y-auto">
            <div className="w-full max-w-3xl flex flex-col items-center text-center space-y-8">
                <div className="space-y-4">
                    <div className="flex items-center justify-center gap-3 mb-2">
                        <div className="w-10 h-10 rounded-xl bg-purple-500/15 border border-purple-500/30 flex items-center justify-center">
                            <Bot className="w-5 h-5 text-purple-400" />
                        </div>
                    </div>
                    <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
                        What should your agent build?
                    </h1>
                    <p className="text-sm sm:text-base text-zinc-400 max-w-xl mx-auto leading-relaxed">
                        Describe any macOS automation workflow in plain English. The Jac compiler turns it into a visual node graph.
                    </p>
                </div>

                <form onSubmit={handle_submit} className="w-full space-y-4">
                    <div className="relative rounded-xl bg-zinc-950 border border-zinc-800 p-5 focus-within:border-purple-500/60 transition-colors group">
                        <textarea
                            rows={4}
                            value={prompt_text}
                            onChange={lambda (event: ChangeEvent) {
                                prompt_text = event.target.value;
                            }}
                            placeholder="e.g. Every morning, check unread emails, summarize the key points with AI, and save the summary in Apple Notes..."
                            aria-label="Describe the workflow to generate"
                            aria-describedby={
                                "ai-builder-status" if status_message else None
                            }
                            className="w-full bg-transparent text-white text-sm placeholder-zinc-400 focus:outline-none resize-none leading-relaxed"
                        />
                        <div className="flex items-center justify-between pt-3 border-t border-zinc-900">
                            <div className="flex items-center gap-2 text-[11px] text-zinc-600 font-mono">
                                <Cpu className="w-3 h-3" />
                                <span>Jac LLM · NVIDIA NIM</span>
                            </div>
                            <button
                                type="submit"
                                disabled={not prompt_text.strip() or is_compiling_prompt}
                                className={
                                    "flex items-center gap-2 px-6 py-2.5 rounded-xl text-xs font-bold transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-purple-400 "
                                    + (
                                        "bg-zinc-800 text-zinc-500 cursor-not-allowed"
                                        if not prompt_text.strip() or is_compiling_prompt
                                        else "bg-white text-zinc-950 hover:bg-zinc-200 active:scale-95"
                                    )
                                }
                            >
                                {if is_compiling_prompt {
                                    <Loader2 className="w-4 h-4 animate-spin text-purple-600" />
                                    <span>Compiling...</span>
                                } elif creates_tool {
                                    <Wrench className="w-4 h-4 text-cyan-700" />
                                    <span>Make Tool</span>
                                } else {
                                    <Wand2 className="w-4 h-4 text-purple-600" />
                                    <span>Generate Workflow</span>
                                }}
                            </button>
                        </div>
                    </div>

                    {if creates_tool {
                        <p role="status" className="flex items-center justify-center gap-1.5 text-[11px] text-cyan-300">
                            <Wrench className="w-3.5 h-3.5" aria-hidden="true" />
                            This request will open the reusable Tool Builder in Actions.
                        </p>
                    }}

                    {if status_message {
                        <div
                            id="ai-builder-status"
                            role={"alert" if status_type == "error" else "status"}
                            aria-live="polite"
                            className={
                                "flex items-start gap-2 rounded-xl px-3 py-2.5 text-left text-xs border "
                                + (
                                    "bg-rose-950/35 border-rose-800/60 text-rose-200"
                                    if status_type == "error"
                                    else (
                                        "bg-emerald-950/30 border-emerald-800/60 text-emerald-200"
                                        if status_type == "success"
                                        else "bg-zinc-900 border-zinc-800 text-zinc-300"
                                    )
                                )
                            }
                        >
                            {if status_type == "error" {
                                <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                            } elif status_type == "success" {
                                <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5" />
                            } else {
                                <Loader2 className="w-4 h-4 shrink-0 mt-0.5 animate-spin" />
                            }}
                            <span className="leading-relaxed">{status_message}</span>
                        </div>
                    }}
                </form>

                <div className="w-full space-y-3 pt-2 text-left">
                    <h3 className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 px-1">
                        Starter Templates
                    </h3>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        {for (index, preset) in enumerate(PRESET_PROMPTS) {
                            <button
                                key={str(index)}
                                type="button"
                                disabled={is_compiling_prompt}
                                onClick={lambda {
                                    prompt_text = str(preset["prompt"]);
                                }}
                                className="p-4 rounded-xl bg-zinc-950 border border-zinc-800 hover:border-zinc-700 hover:bg-zinc-900/60 transition text-left space-y-3 group flex flex-col justify-between disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-purple-400"
                            >
                                <div>
                                    <div className="flex items-center gap-2 mb-2">
                                        <span className="text-base">{preset["icon"]}</span>
                                        <h4 className="text-xs font-bold text-white group-hover:text-purple-300 transition">
                                            {preset["title"]}
                                        </h4>
                                    </div>
                                    <p className="text-[11px] text-zinc-400 line-clamp-3 leading-relaxed">
                                        {preset["description"]}
                                    </p>
                                </div>
                                <div className="flex items-center text-[10px] font-semibold text-purple-400 group-hover:translate-x-1 transition-transform">
                                    <span>Use this prompt</span>
                                    <ArrowRight className="w-3 h-3 ml-1" />
                                </div>
                            </button>
                        }}
                    </div>
                </div>
            </div>

            <button
                onClick={on_switch_to_workflow}
                className="mt-6 flex items-center gap-2 text-xs font-semibold text-zinc-500 hover:text-white transition"
            >
                <ArrowLeft className="w-3.5 h-3.5" />
                <span>Back to Canvas</span>
            </button>
        </div>
    </div>;
}
