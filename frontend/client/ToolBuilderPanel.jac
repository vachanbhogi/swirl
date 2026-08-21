"""Prompt-only builder for reusable, versioned macOS application tools."""

import from react { useEffect }
import from "lucide-react" {
    AlertCircle,
    AppWindow,
    CheckCircle2,
    ChevronDown,
    Code2,
    Loader2,
    Plus,
    RefreshCw,
    Save,
    ShieldCheck,
    Wand2,
    X,
}
import from .data {
    generated_tool_description,
    generated_tool_id,
    generated_tool_inputs,
    generated_tool_name,
    generated_tool_record,
    generated_tool_status,
    generated_tool_version,
}
import from .native_bridge {
    create_generated_tool,
    generate_application_tool,
    publish_generated_tool,
}


def string_items(value: any) -> list[str] {
    if isinstance(value, list) {
        output: list[str] = [];
        for item in (value as list) {
            if isinstance(item, dict) {
                spec: dict = item as dict;
                output.append(str(
                    spec.get("description")
                    or spec.get("label")
                    or spec.get("name")
                    or spec.get("type")
                    or ""
                ));
            } elif item {
                output.append(str(item));
            }
        }
        return [item for item in output if item];
    }
    if isinstance(value, dict) {
        return [
            str(entry[1])
            for entry in (Object.entries(value) as list[list])  # jac:ignore[W2001,W6002]
            if entry[1]
        ];
    }
    return [str(value)] if value else [];
}


def display_target(value: dict) -> str {
    target: dict = (
        value.get("target") as dict
        if isinstance(value.get("target"), dict)
        else {}
    );
    return str(
        target.get("applicationName")
        or target.get("name")
        or value.get("application")
        or "Application not resolved"
    );
}


def generation_draft(value: any) -> dict {
    envelope: dict = value as dict if isinstance(value, dict) else {};
    draft_metadata: dict = (
        envelope.get("draft") as dict
        if isinstance(envelope.get("draft"), dict)
        else {}
    );
    version: dict = (
        envelope.get("version") as dict
        if isinstance(envelope.get("version"), dict)
        else generated_tool_version(envelope)
    );
    snapshot: dict = (
        envelope.get("toolSnapshot") as dict
        if isinstance(envelope.get("toolSnapshot"), dict)
        else {}
    );
    return {
        **draft_metadata,
        **snapshot,
        **version,
        "compiledAutomation": envelope.get("compiledAutomation")
            or version.get("compiledAutomation")
            or {},
        "argumentOrder": envelope.get("argumentOrder") or [],
        "validation": version.get("validation")
            or snapshot.get("validation")
            or envelope.get("validation")
            or {},
        "testStatus": version.get("testStatus")
            or envelope.get("testStatus")
            or "untested",
    };
}


def validation_errors(value: dict) -> list[str] {
    validation: dict = (
        value.get("validation") as dict
        if isinstance(value.get("validation"), dict)
        else {}
    );
    errors: list[str] = string_items(validation.get("errors"));
    if not errors and validation.get("valid") is False {
        errors = string_items(
            validation.get("messages") or validation.get("issues")
        );
    }
    return errors;
}


def:pub ToolBuilderPanel(
    initial_prompt: str = "",
    existing_tool: dict | None = None,
    auto_generate: bool = False,
    on_saved: Callable[[dict, bool], any] | None = None,
    on_close: Callable[[], any] | None = None,
    compact: bool = False,
) -> JsxElement {
    has prompt: str = initial_prompt;
    has draft: dict | None = None;
    has phase: str = "idle";
    has status_message: str = "";
    has auto_generated_prompt: Ref[str] = Ref("");

    can with [initial_prompt, existing_tool] entry {
        prompt = (
            initial_prompt
            or str(
                generated_tool_version(existing_tool or {}).get("sourcePrompt")
                or generated_tool_record(existing_tool or {}).get("sourcePrompt")
                or ""
            )
        );
        draft = (
            {
                **generated_tool_version(existing_tool),
                "displayName": generated_tool_name(existing_tool),
                "description": generated_tool_description(existing_tool),
                "testStatus": generated_tool_status(existing_tool),
            }
            if existing_tool
            else None
        );
        phase = "review" if existing_tool else "idle";
        status_message = "";
    }

    async def handle_generate -> None {
        instruction: str = prompt.strip();
        if not instruction or phase in ["generating", "saving"] { return; }
        phase = "generating";
        status_message = "Reading your request and resolving the installed application…";
        try {
            result = await generate_application_tool(
                instruction,
                generated_tool_id(existing_tool or {}),
            );
            draft = generation_draft(result);
            phase = "review";
            status_message = "Tool draft ready. Review what it can access before saving.";
        } except Exception as error {
            phase = "error";
            status_message = str(error) or "Swirl could not generate this tool.";
        }
    }

    useEffect(lambda {
        instruction: str = initial_prompt.strip();
        if (
            instruction
            and (auto_generate or not existing_tool)
            and auto_generated_prompt.current != instruction
        ) {
            auto_generated_prompt.current = instruction;
            handle_generate();
        }
        return lambda {};
    }, [initial_prompt, existing_tool, auto_generate]);

    async def handle_save(add_to_canvas: bool) -> None {
        if not draft or phase in ["generating", "saving"] { return; }
        if validation_errors(draft) {
            phase = "error";
            status_message = "Resolve the validation issues before saving this tool.";
            return;
        }
        phase = "saving";
        status_message = "Saving the reviewed tool locally…";
        try {
            existing_id: str = generated_tool_id(existing_tool or {});
            result = (
                await publish_generated_tool(existing_id, draft)
                if existing_id
                else await create_generated_tool(draft)
            );
            record: dict = generated_tool_record(result);
            phase = "success";
            status_message = (
                "Saved and added to the canvas."
                if add_to_canvas
                else "Saved to My Tools."
            );
            if on_saved { on_saved(record, add_to_canvas); }
        } except Exception as error {
            phase = "error";
            status_message = str(error) or "The tool could not be saved.";
        }
    }

    def update_draft_field(key: str, value: any) {
        if draft {
            draft = (
                {**draft, "displayName": value, "name": value}
                if key == "displayName"
                else {**draft, key: value}
            );
            if phase == "success" { phase = "review"; }
        }
    }

    is_busy: bool = phase in ["generating", "saving"];
    inputs: list[dict] = generated_tool_inputs(draft or {});
    effects: list[str] = string_items(
        (draft or {}).get("effects")
        or (draft or {}).get("sideEffects")
    );
    permissions: list[str] = string_items(
        (draft or {}).get("requiredPermissions")
        or (draft or {}).get("permissions")
    );
    errors: list[str] = validation_errors(draft or {});
    validation: dict = (
        (draft or {}).get("validation") as dict
        if isinstance((draft or {}).get("validation"), dict)
        else {}
    );
    raw_automation: any = (draft or {}).get("compiledAutomation");
    automation: dict = (
        (draft or {}).get("compiledAutomation") as dict
        if isinstance((draft or {}).get("compiledAutomation"), dict)
        else (
            (draft or {}).get("implementation") as dict
            if isinstance((draft or {}).get("implementation"), dict)
            else {}
        )
    );
    automation_source: str = str(
        raw_automation
        if isinstance(raw_automation, str)
        else automation.get("source")
            or automation.get("script")
            or (
                JSON.stringify((draft or {}).get("program"), None, 2)  # jac:ignore[W2001,W6002]
                if (draft or {}).get("program")
                else ""
            )
    );
    test_status: str = generated_tool_status(draft or {});

    return <section
        aria-label="AI application tool builder"
        className={
            "bg-zinc-950 text-zinc-100 "
            + ("" if compact else "border border-zinc-800 rounded-2xl")
        }
    >
        <div className={"space-y-4 " + ("py-1" if compact else "p-5")}>
            <div className="flex items-start justify-between gap-3">
                <div className="flex items-start gap-3 min-w-0">
                    <div className="w-9 h-9 rounded-xl bg-cyan-950 border border-cyan-800 flex items-center justify-center shrink-0">
                        <Wand2 className="w-4 h-4 text-cyan-300" aria-hidden="true" />
                    </div>
                    <div className="min-w-0">
                        <h3 className="text-sm font-semibold text-white">Make a tool</h3>
                        <p className="mt-0.5 text-[11px] leading-relaxed text-zinc-400">
                            Ask once. Swirl creates a reusable action for an installed Mac app.
                        </p>
                    </div>
                </div>
                {if on_close {
                    <button
                        type="button"
                        onClick={lambda { on_close(); }}
                        aria-label="Close tool builder"
                        className="p-1.5 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                    >
                        <X className="w-4 h-4" aria-hidden="true" />
                    </button>
                }}
            </div>

            <div className="space-y-2">
                <label htmlFor="swirl-tool-prompt" className="text-[11px] font-semibold text-zinc-200">
                    What should the tool do?
                </label>
                <textarea
                    id="swirl-tool-prompt"
                    rows={4 if compact else 5}
                    value={prompt}
                    disabled={is_busy}
                    placeholder="Make a tool to text a friend on Discord"
                    onChange={lambda (event: ChangeEvent) {
                        prompt = event.target.value;
                        if phase in ["error", "success"] {
                            phase = "review" if draft else "idle";
                            status_message = "";
                        }
                    }}
                    className="w-full rounded-xl bg-zinc-900 border border-zinc-700 px-3 py-2.5 text-xs leading-relaxed text-white placeholder:text-zinc-400 focus:outline-none focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 disabled:opacity-60 resize-y"
                />
                <button
                    type="button"
                    onClick={handle_generate}
                    disabled={not prompt.strip() or is_busy}
                    className="w-full min-h-9 flex items-center justify-center gap-2 rounded-xl bg-cyan-600 hover:bg-cyan-500 active:bg-cyan-700 px-3 py-2 text-xs font-semibold text-white transition-colors disabled:bg-zinc-800 disabled:text-zinc-500 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
                >
                    {if phase == "generating" {
                        <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden="true" />
                        <span>Making tool…</span>
                    } else {
                        <Wand2 className="w-3.5 h-3.5" aria-hidden="true" />
                        <span>{"Regenerate draft" if draft else "Make tool"}</span>
                    }}
                </button>
            </div>

            <div
                role={"alert" if phase == "error" else "status"}
                aria-live="polite"
                className={
                    "min-h-0 text-[11px] leading-relaxed "
                    + (
                        "rounded-xl border px-3 py-2.5 "
                        + (
                            "bg-rose-950/40 border-rose-800 text-rose-200"
                            if phase == "error"
                            else (
                                "bg-emerald-950/35 border-emerald-800 text-emerald-200"
                                if phase == "success"
                                else "bg-zinc-900 border-zinc-800 text-zinc-300"
                            )
                        )
                        if status_message
                        else ""
                    )
                }
            >
                {if status_message {
                    <div className="flex items-start gap-2">
                        {if phase == "error" {
                            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" aria-hidden="true" />
                        } elif phase == "success" {
                            <CheckCircle2 className="w-4 h-4 mt-0.5 shrink-0" aria-hidden="true" />
                        } elif is_busy {
                            <Loader2 className="w-4 h-4 mt-0.5 shrink-0 animate-spin" aria-hidden="true" />
                        }}
                        <span>{status_message}</span>
                    </div>
                }}
            </div>

            {if draft {
                <div className="space-y-4 pt-1">
                    <div className="flex items-center justify-between gap-2">
                        <p className="text-[11px] font-semibold text-zinc-200">Review before saving</p>
                        <span className="inline-flex items-center gap-1 rounded-full bg-amber-950/55 border border-amber-800/70 px-2 py-1 text-[10px] font-semibold text-amber-200">
                            <span className="w-1.5 h-1.5 rounded-full bg-amber-400" aria-hidden="true"></span>
                            {"Untested" if test_status == "untested" else test_status.replace("_", " ")}
                        </span>
                    </div>

                    <div className="space-y-3">
                        <label className="block space-y-1">
                            <span className="text-[10px] font-medium text-zinc-400">Tool name</span>
                            <input
                                type="text"
                                value={generated_tool_name(draft)}
                                onChange={lambda (event: ChangeEvent) {
                                    if draft {
                                        draft = {
                                            **draft,
                                            "name": event.target.value,
                                            "displayName": event.target.value,
                                        };
                                    }
                                }}
                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-cyan-500"
                            />
                        </label>
                        <label className="block space-y-1">
                            <span className="text-[10px] font-medium text-zinc-400">Description</span>
                            <textarea
                                rows={2}
                                value={generated_tool_description(draft)}
                                onChange={lambda (event: ChangeEvent) {
                                    update_draft_field("description", event.target.value);
                                }}
                                className="w-full rounded-lg bg-zinc-900 border border-zinc-700 px-3 py-2 text-[11px] leading-relaxed text-zinc-200 focus:outline-none focus:border-cyan-500 resize-y"
                            />
                        </label>
                    </div>

                    <div className="flex items-center gap-2 rounded-xl bg-zinc-900 border border-zinc-800 px-3 py-2.5">
                        <AppWindow className="w-4 h-4 text-cyan-300 shrink-0" aria-hidden="true" />
                        <div className="min-w-0">
                            <p className="text-[10px] text-zinc-500">Resolved application</p>
                            <p className="text-xs font-semibold text-zinc-100 truncate">{display_target(draft)}</p>
                        </div>
                    </div>

                    <div className="space-y-2">
                        <p className="text-[10px] font-semibold text-zinc-400">Inputs</p>
                        {if inputs {
                            <div className="space-y-1.5">
                                {for input_spec in inputs {
                                    input_key: str = str(input_spec.get("key") or input_spec.get("name") or "input");
                                    <div key={input_key} className="flex items-center justify-between gap-3 rounded-lg bg-zinc-900 px-3 py-2">
                                        <span className="text-[11px] text-zinc-200 truncate">
                                            {input_spec.get("label") or input_key}
                                            {if input_spec.get("required") {
                                                <span className="text-rose-300" aria-label="required"> *</span>
                                            }}
                                        </span>
                                        <code className="text-[10px] text-zinc-400 font-mono shrink-0">
                                            {input_spec.get("inputType") or input_spec.get("type") or "text"}
                                        </code>
                                    </div>
                                }}
                            </div>
                        } else {
                            <p className="text-[11px] text-zinc-500">No inputs required.</p>
                        }}
                    </div>

                    <div className="space-y-3">
                        <div>
                            <p className="text-[10px] font-semibold text-zinc-400 mb-1.5">What it can do</p>
                            <ul className="space-y-1.5">
                                {for (index, effect) in enumerate(effects or ["Control " + display_target(draft) + " when you run this block."]) {
                                    <li key={str(index)} className="flex items-start gap-2 text-[11px] leading-relaxed text-zinc-300">
                                        <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 text-cyan-400 shrink-0" aria-hidden="true" />
                                        <span>{effect}</span>
                                    </li>
                                }}
                            </ul>
                        </div>
                        <div>
                            <p className="text-[10px] font-semibold text-zinc-400 mb-1.5">Permissions</p>
                            <ul className="space-y-1.5">
                                {for (index, permission) in enumerate(permissions or ["Approval before each external action"]) {
                                    <li key={str(index)} className="flex items-start gap-2 text-[11px] leading-relaxed text-zinc-300">
                                        <ShieldCheck className="w-3.5 h-3.5 mt-0.5 text-emerald-400 shrink-0" aria-hidden="true" />
                                        <span>{permission}</span>
                                    </li>
                                }}
                            </ul>
                        </div>
                    </div>

                    <div className={
                        "rounded-xl border px-3 py-2.5 "
                        + (
                            "bg-rose-950/35 border-rose-800/70"
                            if errors
                            else "bg-emerald-950/25 border-emerald-900/70"
                        )
                    }>
                        <div className="flex items-center gap-2">
                            {if errors {
                                <AlertCircle className="w-4 h-4 text-rose-300" aria-hidden="true" />
                            } else {
                                <ShieldCheck className="w-4 h-4 text-emerald-300" aria-hidden="true" />
                            }}
                            <p className={"text-[11px] font-semibold " + ("text-rose-200" if errors else "text-emerald-200")}>
                                {"Validation needs attention" if errors else (validation.get("message") or "Safety validation passed")}
                            </p>
                        </div>
                        {if errors {
                            <ul className="mt-2 pl-5 list-disc space-y-1 text-[10px] text-rose-200">
                                {for (index, error) in enumerate(errors) {
                                    <li key={str(index)}>{error}</li>
                                }}
                            </ul>
                        }}
                    </div>

                    <details className="group rounded-xl bg-zinc-900 border border-zinc-800">
                        <summary className="flex items-center justify-between gap-2 px-3 py-2.5 cursor-pointer text-[11px] font-medium text-zinc-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-cyan-400">
                            <span className="flex items-center gap-2">
                                <Code2 className="w-3.5 h-3.5 text-zinc-400" aria-hidden="true" />
                                Generated automation
                            </span>
                            <ChevronDown className="w-3.5 h-3.5 text-zinc-500 transition-transform group-open:rotate-180" aria-hidden="true" />
                        </summary>
                        <div className="border-t border-zinc-800 p-3">
                            <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words select-text text-[10px] leading-relaxed font-mono text-zinc-300">
                                {automation_source or "Automation source will be available after generation."}
                            </pre>
                        </div>
                    </details>

                    <div className="grid grid-cols-2 gap-2 pt-1">
                        <button
                            type="button"
                            onClick={handle_generate}
                            disabled={is_busy}
                            className="flex items-center justify-center gap-1.5 rounded-xl bg-zinc-900 border border-zinc-700 hover:bg-zinc-800 px-3 py-2 text-xs font-semibold text-zinc-200 disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                        >
                            <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
                            Regenerate
                        </button>
                        <button
                            type="button"
                            onClick={lambda { handle_save(False); }}
                            disabled={is_busy or bool(errors)}
                            className="flex items-center justify-center gap-1.5 rounded-xl bg-zinc-800 hover:bg-zinc-700 px-3 py-2 text-xs font-semibold text-white disabled:text-zinc-500 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
                        >
                            <Save className="w-3.5 h-3.5" aria-hidden="true" />
                            Save
                        </button>
                        <button
                            type="button"
                            onClick={lambda { handle_save(True); }}
                            disabled={is_busy or bool(errors)}
                            className="col-span-2 flex items-center justify-center gap-1.5 rounded-xl bg-cyan-600 hover:bg-cyan-500 active:bg-cyan-700 px-3 py-2.5 text-xs font-semibold text-white disabled:bg-zinc-800 disabled:text-zinc-500 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
                        >
                            {if phase == "saving" {
                                <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden="true" />
                            } else {
                                <Plus className="w-3.5 h-3.5" aria-hidden="true" />
                            }}
                            Save &amp; add to canvas
                        </button>
                    </div>
                </div>
            }}
        </div>
    </section>;
}
