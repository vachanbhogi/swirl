import React, { useState, useRef } from 'react';
import { 
  ZoomIn, 
  ZoomOut, 
  Maximize2, 
  Compass, 
  Settings, 
  Trash2, 
  CheckCircle2, 
  Loader2,
  Zap,
  Sparkles,
  Command,
  Plug,
  GitBranch,
  Send
} from 'lucide-react';
import { BLOCK_CATEGORIES } from '../data/blockDefinitions';

const ICON_MAP = { Zap, Sparkles, Command, Plug, GitBranch, Send };

export default function WhiteboardCard({
  nodes,
  setNodes,
  edges,
  setEdges,
  activeNodeId,
  selectedNodeId,
  setSelectedNodeId,
  onOpenConfigModal,
  onDropNewBlock
}) {
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [isPanning, setIsPanning] = useState(false);
  const [draggingNodeId, setDraggingNodeId] = useState(null);
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
  const [connectingPort, setConnectingPort] = useState(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  const panRef = useRef({ startX: 0, startY: 0, initialX: 0, initialY: 0 });
  const canvasRef = useRef(null);

  // Mouse move handler for panning, node movement, and wire preview
  const handleMouseMove = (e) => {
    if (!canvasRef.current) return;
    const rect = canvasRef.current.getBoundingClientRect();
    const currentX = (e.clientX - rect.left - pan.x) / zoom;
    const currentY = (e.clientY - rect.top - pan.y) / zoom;

    setMousePos({ x: currentX, y: currentY });

    if (draggingNodeId) {
      setNodes((prevNodes) =>
        prevNodes.map((n) =>
          n.id === draggingNodeId
            ? { ...n, x: Math.round(currentX - dragOffset.x), y: Math.round(currentY - dragOffset.y) }
            : n
        )
      );
    } else if (isPanning) {
      const dx = e.clientX - panRef.current.startX;
      const dy = e.clientY - panRef.current.startY;
      setPan({
        x: panRef.current.initialX + dx,
        y: panRef.current.initialY + dy
      });
    }
  };

  const handleMouseDown = (e) => {
    // Only pan if background is clicked
    if (e.target === canvasRef.current || e.target.tagName === 'svg' || e.target.classList.contains('canvas-bg')) {
      setIsPanning(true);
      panRef.current = {
        startX: e.clientX,
        startY: e.clientY,
        initialX: pan.x,
        initialY: pan.y
      };
    }
  };

  const handleMouseUp = () => {
    setIsPanning(false);
    setDraggingNodeId(null);
    setConnectingPort(null);
  };

  const handleWheel = (e) => {
    e.preventDefault();
    const zoomFactor = e.deltaY < 0 ? 1.05 : 0.95;
    setZoom((prevZoom) => Math.min(Math.max(prevZoom * zoomFactor, 0.4), 2.5));
  };

  const resetCamera = () => {
    setPan({ x: 0, y: 0 });
    setZoom(1);
  };

  // Drag over & Drop new block from tool library
  const handleDragOver = (e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'copy';
  };

  const handleDrop = (e) => {
    e.preventDefault();
    const rawData = e.dataTransfer.getData('application/swirl-block');
    if (!rawData || !canvasRef.current) return;

    try {
      const blockDef = JSON.parse(rawData);
      const rect = canvasRef.current.getBoundingClientRect();
      const dropX = (e.clientX - rect.left - pan.x) / zoom - 120;
      const dropY = (e.clientY - rect.top - pan.y) / zoom - 40;

      onDropNewBlock(blockDef, Math.max(20, dropX), Math.max(20, dropY));
    } catch (err) {
      console.error('Failed to parse dropped block:', err);
    }
  };

  const handleNodeMouseDown = (e, node) => {
    e.stopPropagation();
    setSelectedNodeId(node.id);
    setDraggingNodeId(node.id);

    const rect = canvasRef.current.getBoundingClientRect();
    const currentX = (e.clientX - rect.left - pan.x) / zoom;
    const currentY = (e.clientY - rect.top - pan.y) / zoom;

    setDragOffset({
      x: currentX - node.x,
      y: currentY - node.y
    });
  };

  // Port Connection Handlers
  const handlePortMouseDown = (e, nodeId, portName, isOutput) => {
    e.stopPropagation();
    setConnectingPort({ nodeId, portName, isOutput });
  };

  const handlePortMouseUp = (e, targetNodeId, targetPortName, isTargetOutput) => {
    e.stopPropagation();
    if (!connectingPort) return;

    if (connectingPort.nodeId !== targetNodeId && connectingPort.isOutput !== isTargetOutput) {
      const sourceId = connectingPort.isOutput ? connectingPort.nodeId : targetNodeId;
      const targetId = connectingPort.isOutput ? targetNodeId : connectingPort.nodeId;
      const sourcePort = connectingPort.isOutput ? connectingPort.portName : targetPortName;
      const targetPort = connectingPort.isOutput ? targetPortName : connectingPort.portName;

      const newEdgeId = `edge-${sourceId}-${targetId}`;

      if (!edges.some((edge) => edge.source === sourceId && edge.target === targetId)) {
        setEdges((prev) => [...prev, { id: newEdgeId, source: sourceId, target: targetId, sourcePort, targetPort }]);
      }
    }
    setConnectingPort(null);
  };

  const handleDeleteNode = (e, nodeId) => {
    e.stopPropagation();
    setNodes((prev) => prev.filter((n) => n.id !== nodeId));
    setEdges((prev) => prev.filter((edge) => edge.source !== nodeId && edge.target !== nodeId));
    if (selectedNodeId === nodeId) setSelectedNodeId(null);
  };

  const getNodePortPos = (nodeId, isOutput) => {
    const node = nodes.find((n) => n.id === nodeId);
    if (!node) return { x: 0, y: 0 };
    return {
      x: isOutput ? node.x + 260 : node.x,
      y: node.y + 40
    };
  };

  return (
    <div className="absolute inset-0 pt-20 pl-6 pr-80 pb-6 pointer-events-auto select-none flex flex-col">
      <div className="w-full h-full rounded-3xl bg-white border border-neutral-300 shadow-2xl flex flex-col overflow-hidden relative">
        {/* Header / Canvas Control Bar */}
        <div className="h-11 px-6 bg-neutral-100 border-b border-neutral-200 flex items-center justify-between z-20">
          <div className="flex items-center gap-2 text-neutral-600">
            <Compass className="w-4 h-4 text-neutral-500" />
            <span className="text-xs font-mono font-medium text-neutral-700">Whiteboard Canvas</span>
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-neutral-200 text-neutral-600">
              {Math.round(zoom * 100)}%
            </span>
            <span className="text-[11px] text-neutral-400 font-mono hidden sm:inline ml-2">
              Nodes: {nodes.length} | Edges: {edges.length}
            </span>
          </div>

          {/* Camera Controls */}
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setZoom((z) => Math.min(z + 0.15, 2.5))}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Zoom In"
            >
              <ZoomIn className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={() => setZoom((z) => Math.max(z - 0.15, 0.4))}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Zoom Out"
            >
              <ZoomOut className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={resetCamera}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Reset Camera View"
            >
              <Maximize2 className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Interactive Infinite Canvas Container */}
        <div 
          ref={canvasRef}
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
          onWheel={handleWheel}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          className={`flex-1 relative overflow-hidden bg-white canvas-bg cursor-grab ${
            isPanning ? 'cursor-grabbing' : ''
          }`}
        >
          {/* Zoomable & Pannable Viewport */}
          <div 
            style={{
              transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
              transformOrigin: '0 0'
            }}
            className="absolute inset-0 w-full h-full pointer-events-auto"
          >
            {/* SVG Wire Edges Layer */}
            <svg className="absolute inset-0 w-[5000px] h-[5000px] pointer-events-none z-0">
              {edges.map((edge) => {
                const srcPos = getNodePortPos(edge.source, true);
                const tgtPos = getNodePortPos(edge.target, false);
                const deltaX = Math.abs(tgtPos.x - srcPos.x) * 0.5;
                const pathD = `M ${srcPos.x} ${srcPos.y} C ${srcPos.x + deltaX} ${srcPos.y}, ${tgtPos.x - deltaX} ${tgtPos.y}, ${tgtPos.x} ${tgtPos.y}`;

                return (
                  <path
                    key={edge.id}
                    d={pathD}
                    fill="none"
                    stroke="#404040"
                    strokeWidth="2.5"
                    strokeDasharray="4"
                  />
                );
              })}

              {/* Connecting Wire Drag Preview */}
              {connectingPort && (
                <path
                  d={`M ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).x} ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).y} Q ${mousePos.x} ${mousePos.y}, ${mousePos.x} ${mousePos.y}`}
                  fill="none"
                  stroke="#171717"
                  strokeWidth="2.5"
                  strokeDasharray="4"
                />
              )}
            </svg>

            {/* Interactive Block Nodes Layer */}
            {nodes.map((node) => {
              const catObj = BLOCK_CATEGORIES.find((c) => c.id === node.category) || BLOCK_CATEGORIES[0];
              const IconComp = ICON_MAP[catObj.icon] || Zap;
              const isSelected = selectedNodeId === node.id;
              const isRunning = activeNodeId === node.id;

              return (
                <div
                  key={node.id}
                  onMouseDown={(e) => handleNodeMouseDown(e, node)}
                  style={{ left: `${node.x}px`, top: `${node.y}px`, width: '270px' }}
                  className={`scratch-block block-cat-${node.category} ${
                    isRunning ? 'node-running' : ''
                  } ${node.status === 'success' ? 'node-success' : ''} ${
                    isSelected ? 'selected' : ''
                  } absolute z-10 p-3.5 rounded-xl border relative shadow-xl transition-transform hover:-translate-y-0.5`}
                >
                  {/* Left Connection Port */}
                  <div
                    onMouseUp={(e) => handlePortMouseUp(e, node.id, 'in', false)}
                    onMouseDown={(e) => handlePortMouseDown(e, node.id, 'in', false)}
                    className="block-port absolute -left-2 top-[34px] z-20 shadow-md"
                    title="Input Port"
                  />

                  {/* Right Connection Port */}
                  <div
                    onMouseUp={(e) => handlePortMouseUp(e, node.id, 'out', true)}
                    onMouseDown={(e) => handlePortMouseDown(e, node.id, 'out', true)}
                    className="block-port absolute -right-2 top-[34px] z-20 shadow-md"
                    title="Output Port"
                  />

                  {/* Node Header */}
                  <div className="flex items-center justify-between pb-2 mb-2 border-b border-white/10">
                    <div className="flex items-center gap-2 overflow-hidden">
                      <div
                        className="w-7 h-7 rounded-lg flex items-center justify-center text-white shrink-0 shadow-sm"
                        style={{ backgroundColor: catObj.color }}
                      >
                        <IconComp className="w-4 h-4" />
                      </div>
                      <div className="overflow-hidden">
                        <h4 className="text-xs font-bold text-slate-100 truncate">{node.title}</h4>
                        <p className="text-[10px] text-slate-400 font-mono truncate">
                          {node.category.toUpperCase()} • {node.type}
                        </p>
                      </div>
                    </div>

                    <div className="flex items-center gap-1 shrink-0">
                      {isRunning && <Loader2 className="w-4 h-4 text-amber-400 animate-spin" />}
                      {node.status === 'success' && <CheckCircle2 className="w-4 h-4 text-emerald-400" />}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onOpenConfigModal(node);
                        }}
                        className="p-1 rounded bg-white/10 hover:bg-white/20 text-slate-300 hover:text-white transition"
                        title="Edit Parameters"
                      >
                        <Settings className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={(e) => handleDeleteNode(e, node.id)}
                        className="p-1 rounded bg-white/10 hover:bg-rose-500/30 text-slate-400 hover:text-rose-300 transition"
                        title="Delete Node"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>

                  {/* Node Config Summary */}
                  <div className="bg-slate-950/70 rounded-lg p-2 text-[10px] font-mono text-slate-300 space-y-1 border border-white/10">
                    {Object.entries(node.config || {}).slice(0, 2).map(([k, v]) => (
                      <div key={k} className="flex justify-between items-center text-[10px]">
                        <span className="text-slate-400">{k}:</span>
                        <span className="text-amber-300 font-semibold truncate max-w-[110px]">
                          {typeof v === 'object' ? JSON.stringify(v) : String(v)}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
