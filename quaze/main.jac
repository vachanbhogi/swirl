"""QuaZe prompt-to-agentic-workflow full-stack entry point."""

import from endpoints {
    compile_prompt,
    validate_workflow,
    reorder_blocks,
    start_run,
    approve_run,
    get_run
}

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
