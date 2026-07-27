"""Interactive pan, zoom, drag, and graph-connection canvas."""

import from "lucide-react" {
    ZoomIn,
    ZoomOut,
    Maximize2,
    Settings,
    Trash2,
    CheckCircle2,
    Loader2,
    Zap,
    Sparkles,
    Command,
    Plug,
    GitBranch,
    Send,
    Radio,
}

glob NODE_WIDTH: int = 270;
glob PORT_CENTER_Y: int = 42;
glob GRID_SIZE: int = 24;


def get_wire_path(source: dict, target: dict) -> str {
    horizontal_gap: float = (
        (target["x"] as float) - (source["x"] as float)
    );
    absolute_gap: float = (
        -horizontal_gap if horizontal_gap < 0.0 else horizontal_gap
    );
    candidate_bend: float = absolute_gap * 0.5;
    bend: float = (
        72.0
        if candidate_bend < 72.0
        else (220.0 if candidate_bend > 220.0 else candidate_bend)
    );
    return (
        "M " + str(source["x"]) + " " + str(source["y"])
        + " C " + str(float(source["x"]) + bend) + " " + str(source["y"])
        + ", " + str(float(target["x"]) - bend) + " " + str(target["y"])
        + ", " + str(target["x"]) + " " + str(target["y"])
    );
}


def category_definition(category: str, block_categories: list[dict]) -> dict {
    for definition in block_categories {
        if definition["id"] == category { return definition; }
    }
    return block_categories[0];
}


def category_icon(icon_name: str) -> any {
    if icon_name == "Sparkles" { return Sparkles; }
    if icon_name == "Command" { return Command; }
    if icon_name == "Plug" { return Plug; }
    if icon_name == "GitBranch" { return GitBranch; }
    if icon_name == "Send" { return Send; }
    if icon_name == "Radio" { return Radio; }
    return Zap;
}


def:pub WhiteboardCard(
    block_categories: list[dict],
    nodes: list,
    set_nodes: Callable[[list], any],
    edges: list,
    set_edges: Callable[[list], any],
    active_node_id: str | None,
    selected_node_id: str | None,
    set_selected_node_id: Callable[[str | None], any],
    on_drop_new_block: Callable[[dict, float, float], any],
) -> JsxElement {
    has pan: dict = {"x": 0.0, "y": 0.0};
    has zoom: float = 1.0;
    has is_panning: bool = False;
    has dragging_node_id: str | None = None;
    has drag_offset: dict = {"x": 0.0, "y": 0.0};
    has connecting_port: dict | None = None;
    has mouse_pos: dict = {"x": 0.0, "y": 0.0};
    has pan_ref: Ref[dict] = Ref({
        "startX": 0.0,
        "startY": 0.0,
        "initialX": 0.0,
        "initialY": 0.0,
    });
    has canvas_ref: Ref[HTMLDivElement] = Ref();

    def handle_mouse_move(event: any) {
        if not canvas_ref.current { return; }
        rect: any = canvas_ref.current.getBoundingClientRect();
        current_x: float = (
            float(event.clientX) - float(rect.left) - (pan["x"] as float)
        ) / zoom;
        current_y: float = (
            float(event.clientY) - float(rect.top) - (pan["y"] as float)
        ) / zoom;
        mouse_pos = {"x": current_x, "y": current_y};

        if dragging_node_id {
            next_nodes: list = [];
            for workflow_node in nodes {
                if workflow_node["id"] == dragging_node_id {
                    x: float = current_x - float(drag_offset["x"]);
                    y: float = current_y - float(drag_offset["y"]);
                    next_nodes.append(
                        {
                            **workflow_node,
                            "x": x,
                            "y": y,
                            "position": {"x": x, "y": y},
                        }
                    );
                } else {
                    next_nodes.append(workflow_node);
                }
            }
            set_nodes(next_nodes);
        } elif is_panning and pan_ref.current {
            pan = {
                    "x": (pan_ref.current["initialX"] as float)
                    + float(event.clientX)
                    - float(pan_ref.current["startX"]),
                    "y": (pan_ref.current["initialY"] as float)
                    + float(event.clientY)
                    - float(pan_ref.current["startY"]),
            };
        }
    }

    def handle_mouse_down(event: any) {
        if not canvas_ref.current { return; }
        target = event.target;
        if (
            target == canvas_ref.current
            or target.classList.contains("canvas-viewport")
            or target.tagName == "svg"
            or target.classList.contains("canvas-bg")
            or target.classList.contains("canvas-grid-figma")
        ) {
            is_panning = True;
            pan_ref.current = {
                "startX": event.clientX,
                "startY": event.clientY,
                "initialX": pan["x"],
                "initialY": pan["y"],
            };
        }
    }

    def handle_mouse_up(_event: any) {
        is_panning = False;
        dragging_node_id = None;
        connecting_port = None;
    }

    def handle_wheel(event: any) {
        event.preventDefault();
        factor: float = 1.05 if event.deltaY < 0 else 0.95;
        zoom = min(max(zoom * factor, 0.4), 2.2);
    }

    def reset_camera(_event: MouseEvent) {
        pan = {"x": 0.0, "y": 0.0};
        zoom = 1.0;
    }

    def handle_drag_over(event: any) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
    }

    def handle_drop(event: any) {
        event.preventDefault();
        raw_data: str = str(
            event.dataTransfer.getData("application/swirl-block")
        );
        if not raw_data or not canvas_ref.current { return; }
        try {
            block_definition: dict = JSON.parse(raw_data) as dict;  # jac:ignore[W2001,W6002]
            rect: any = canvas_ref.current.getBoundingClientRect();
            drop_x: float = (
                (float(event.clientX) - float(rect.left) - (pan["x"] as float)) / zoom
                - 135.0
            );
            drop_y: float = (
                (float(event.clientY) - float(rect.top) - (pan["y"] as float)) / zoom
                - 40.0
            );
            on_drop_new_block(
                block_definition,
                max(20.0, drop_x),
                max(20.0, drop_y),
            );
        } except Exception as error {
            console.error("Failed to parse dropped block:", error);  # jac:ignore[W2001,W6002]
        }
    }

    def handle_node_mouse_down(event: any, workflow_node: dict) {
        event.stopPropagation();
        set_selected_node_id(str(workflow_node["id"]));
        dragging_node_id = str(workflow_node["id"]);
        if not canvas_ref.current { return; }
        rect: any = canvas_ref.current.getBoundingClientRect();
        current_x: float = (
            float(event.clientX) - float(rect.left) - (pan["x"] as float)
        ) / zoom;
        current_y: float = (
            float(event.clientY) - float(rect.top) - (pan["y"] as float)
        ) / zoom;
        drag_offset = {
            "x": current_x - (workflow_node["x"] as float),
            "y": current_y - (workflow_node["y"] as float),
        };
    }

    def handle_port_mouse_down(
        event: any,
        node_id: str,
        port_name: str,
        is_output: bool,
    ) {
        event.stopPropagation();
        connecting_port = {
            "nodeId": node_id,
            "portName": port_name,
            "isOutput": is_output,
        };
    }

    def handle_port_mouse_up(
        event: any,
        target_node_id: str,
        target_port_name: str,
        is_target_output: bool,
    ) {
        event.stopPropagation();
        if not connecting_port { return; }
        origin_id: str = str(connecting_port["nodeId"]);
        origin_is_output: bool = bool(connecting_port["isOutput"]);
        if origin_id != target_node_id and origin_is_output != is_target_output {
            source_id: str = origin_id if origin_is_output else target_node_id;
            target_id: str = target_node_id if origin_is_output else origin_id;
            source_port: str = (
                str(connecting_port["portName"])
                if origin_is_output
                else target_port_name
            );
            target_port: str = (
                target_port_name
                if origin_is_output
                else str(connecting_port["portName"])
            );
            exists: bool = `any(
                edge["source"] == source_id and edge["target"] == target_id
                for edge in edges
            );
            if not exists {
                set_edges(
                    edges
                    + [{
                        "id": f"edge-{source_id}-{target_id}",
                        "source": source_id,
                        "target": target_id,
                        "sourcePort": source_port,
                        "targetPort": target_port,
                    }]
                );
            }
        }
        connecting_port = None;
    }

    def handle_delete_node(event: any, node_id: str) {
        event.stopPropagation();
        for workflow_node in nodes {
            if (
                workflow_node["id"] == node_id
                and workflow_node["category"] == "source"
            ) { return; }
        }
        set_nodes([
            workflow_node
            for workflow_node in nodes
            if workflow_node["id"] != node_id
        ]);
        set_edges([
            edge
            for edge in edges
            if edge["source"] != node_id and edge["target"] != node_id
        ]);
        if selected_node_id == node_id { set_selected_node_id(None); }
    }

    def node_port_position(node_id: str, is_output: bool) -> dict {
        for workflow_node in nodes {
            if workflow_node["id"] == node_id {
                return {
                    "x": (
                        (workflow_node["x"] as float) + NODE_WIDTH
                        if is_output
                        else (workflow_node["x"] as float)
                    ),
                    "y": (workflow_node["y"] as float) + PORT_CENTER_Y,
                };
            }
        }
        return {"x": 0.0, "y": 0.0};
    }

    preview_anchor: dict | None = (
        node_port_position(
            str(connecting_port["nodeId"]),
            bool(connecting_port["isOutput"]),
        )
        if connecting_port
        else None
    );
    preview_path: str | None = None;
    if preview_anchor and connecting_port {
        preview_path = get_wire_path(
            preview_anchor if connecting_port["isOutput"] else mouse_pos,
            mouse_pos if connecting_port["isOutput"] else preview_anchor,
        );
    }

    return <div className="w-full h-full relative overflow-hidden select-none flex-1">
        <div
            ref={canvas_ref}
            onMouseDown={handle_mouse_down}
            onMouseMove={handle_mouse_move}
            onMouseUp={handle_mouse_up}
            onMouseLeave={handle_mouse_up}
            onWheel={handle_wheel}
            onDragOver={handle_drag_over}
            onDrop={handle_drop}
            style={{
                "--canvas-grid-size": str(GRID_SIZE * zoom) + "px",
                "--canvas-grid-x": str(pan["x"]) + "px",
                "--canvas-grid-y": str(pan["y"]) + "px",
            }}
            className={
                "w-full h-full relative overflow-hidden canvas-bg canvas-grid-figma cursor-grab "
                + ("cursor-grabbing" if is_panning else "")
            }
        >
            <div
                style={{
                    "transform": "translate(" + str(pan["x"]) + "px, "
                        + str(pan["y"]) + "px) scale(" + str(zoom) + ")",
                    "transformOrigin": "0 0",
                }}
                className="absolute inset-0 w-full h-full pointer-events-auto canvas-viewport"
            >
                <svg className="absolute inset-0 w-[6000px] h-[6000px] pointer-events-none z-0">
                    {for edge in edges {
                        source_position: dict = node_port_position(
                            str(edge["source"]), True
                        );
                        target_position: dict = node_port_position(
                            str(edge["target"]), False
                        );
                        path_data: str = get_wire_path(
                            source_position, target_position
                        );
                        edge_active: bool = (
                            active_node_id == edge["source"]
                            or active_node_id == edge["target"]
                        );
                        <g key={str(edge["id"])} data-edge-id={edge["id"]}>
                            <path
                                d={path_data}
                                fill="none"
                                stroke="rgba(255, 255, 255, 0.92)"
                                strokeWidth="5"
                                strokeLinecap="round"
                                vectorEffect="non-scaling-stroke"
                            />
                            <path
                                d={path_data}
                                fill="none"
                                stroke={"#8B5CF6" if edge_active else "#64748B"}
                                strokeWidth="2.5"
                                strokeDasharray="6 6"
                                strokeLinecap="round"
                                vectorEffect="non-scaling-stroke"
                                className={
                                    "wire-path-active"
                                    if edge_active
                                    else "wire-path-figma"
                                }
                            />
                        </g>
                    }}
                    {if connecting_port and preview_path {
                        <path
                            d={preview_path}
                            fill="none"
                            stroke="#7C3AED"
                            strokeWidth="2.5"
                            strokeDasharray="6 6"
                            strokeLinecap="round"
                            vectorEffect="non-scaling-stroke"
                            className="wire-preview"
                        />
                    }}
                </svg>

                {for workflow_node in nodes {
                    category: dict = category_definition(
                        str(workflow_node["category"]),
                        block_categories,
                    );
                    icon_component = category_icon(str(category["icon"]));
                    node_id: str = str(workflow_node["id"]);
                    is_selected: bool = selected_node_id == node_id;
                    is_running: bool = active_node_id == node_id;
                    is_dragging: bool = dragging_node_id == node_id;
                    config_entries: list = (
                        Object.entries(workflow_node["config"] or {})[:2] as list
                    );  # jac:ignore[W2001,W6002]
                    <div
                        key={node_id}
                        data-node-id={node_id}
                        onMouseDown={lambda (event: MouseEvent) {
                            handle_node_mouse_down(event, workflow_node);
                        }}
                        style={{
                            "left": str(workflow_node["x"]) + "px",
                            "top": str(workflow_node["y"]) + "px",
                            "width": str(NODE_WIDTH) + "px",
                        }}
                        className={
                            "figma-node-card absolute z-10 p-4 font-sans text-left cursor-grab active:cursor-grabbing bg-zinc-950 border border-zinc-800 rounded-2xl shadow-xl transition-[border-color,box-shadow] duration-150 ease-out hover:shadow-2xl text-zinc-100 "
                            + ("running " if is_running else "")
                            + (
                                "success "
                                if workflow_node["status"] == "success"
                                else ""
                            )
                            + ("selected " if is_selected else "")
                            + ("dragging" if is_dragging else "")
                        }
                    >
                        <div
                            onMouseUp={lambda (event: MouseEvent) {
                                handle_port_mouse_up(event, node_id, "in", False);
                            }}
                            onMouseDown={lambda (event: MouseEvent) {
                                handle_port_mouse_down(event, node_id, "in", False);
                            }}
                            className="group/port absolute -left-2 top-[34px] z-20 w-4 h-4 rounded-full border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 hover:border-zinc-500 flex items-center justify-center cursor-crosshair shadow-sm transition-transform hover:scale-125"
                            title="Input Port"
                        >
                            <span className="w-1.5 h-1.5 rounded-full bg-zinc-400" />
                        </div>
                        <div
                            onMouseUp={lambda (event: MouseEvent) {
                                handle_port_mouse_up(event, node_id, "out", True);
                            }}
                            onMouseDown={lambda (event: MouseEvent) {
                                handle_port_mouse_down(event, node_id, "out", True);
                            }}
                            className="group/port absolute -right-2 top-[34px] z-20 w-4 h-4 rounded-full border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 hover:border-zinc-500 flex items-center justify-center cursor-crosshair shadow-sm transition-transform hover:scale-125"
                            title="Output Port"
                        >
                            <span className="w-1.5 h-1.5 rounded-full bg-zinc-400" />
                        </div>

                        <div className="flex items-center justify-between pb-3 mb-3 border-b border-zinc-800/80">
                            <div className="flex items-center gap-2.5 overflow-hidden">
                                <div
                                    className="w-8 h-8 rounded-xl flex items-center justify-center text-white shrink-0 shadow-sm"
                                    style={{"backgroundColor": category["color"]}}
                                >
                                    <@icon_component className="w-4.5 h-4.5" />
                                </div>
                                <div className="overflow-hidden">
                                    <h4 className="text-xs font-bold text-white truncate font-sans">
                                        {workflow_node["title"]}
                                    </h4>
                                    <p className="text-[10px] text-zinc-400 font-sans truncate">
                                        {
                                            "ENTRYPOINT TRIGGER"
                                            if workflow_node["category"] == "source"
                                            else category["name"]
                                        }
                                    </p>
                                </div>
                            </div>
                            <div className="flex items-center gap-1 shrink-0">
                                {if is_running {
                                    <Loader2 className="w-4 h-4 text-purple-400 animate-spin" />
                                }}
                                {if workflow_node["status"] == "success" {
                                    <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                                }}
                                {if workflow_node["category"] != "source" {
                                    <button
                                        onClick={lambda (event: MouseEvent) {
                                            event.stopPropagation();
                                            set_selected_node_id(node_id);
                                        }}
                                        className="p-1 rounded-lg hover:bg-zinc-800 text-zinc-400 hover:text-white transition"
                                        title="Configure Block"
                                    >
                                        <Settings className="w-3.5 h-3.5" />
                                    </button>
                                    <button
                                        onClick={lambda (event: MouseEvent) {
                                            handle_delete_node(event, node_id);
                                        }}
                                        className="p-1 rounded-lg hover:bg-rose-950/60 text-zinc-400 hover:text-rose-400 transition"
                                        title="Delete Block"
                                    >
                                        <Trash2 className="w-3.5 h-3.5" />
                                    </button>
                                }}
                            </div>
                        </div>
                        <div className="bg-zinc-900/90 rounded-xl p-2.5 text-[11px] text-zinc-300 space-y-1 border border-zinc-800/80">
                            {for item in config_entries {
                                key: str = str(item[0]);
                                value = item[1];
                                <div
                                    key={key}
                                    className="flex justify-between items-center text-[10px]"
                                >
                                    <span className="text-zinc-400 capitalize">
                                        {key + ":"}
                                    </span>
                                    <span className="font-semibold text-zinc-200 truncate max-w-[120px]">
                                        {
                                            JSON.stringify(value)
                                            if isinstance(value, dict)
                                            else str(value)
                                        }
                                    </span>
                                </div>
                            }}
                        </div>
                    </div>
                }}
            </div>
        </div>

        <div className="absolute bottom-6 right-6 z-20 flex items-center gap-1.5 bg-zinc-900/95 text-zinc-200 backdrop-blur-xl p-1.5 rounded-2xl border border-zinc-800 shadow-xl select-none">
            <button
                onClick={lambda { zoom = min(zoom + 0.15, 2.2); }}
                className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
                title="Zoom In"
            >
                <ZoomIn className="w-4 h-4" />
            </button>
            <span className="text-xs font-mono font-bold text-zinc-200 px-2 min-w-[48px] text-center">
                {str(round(zoom * 100)) + "%"}
            </span>
            <button
                onClick={lambda { zoom = max(zoom - 0.15, 0.4); }}
                className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
                title="Zoom Out"
            >
                <ZoomOut className="w-4 h-4" />
            </button>
            <div className="h-4 w-px bg-zinc-800 mx-1" />
            <button
                onClick={reset_camera}
                className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
                title="Reset Zoom to 100%"
            >
                <Maximize2 className="w-4 h-4" />
            </button>
        </div>
    </div>;
}
