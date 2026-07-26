import React, { useState, useRef } from 'react';
import { 
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
  Radio
} from 'lucide-react';
import { BLOCK_CATEGORIES } from '../data/blockDefinitions';

const ICON_MAP = { Zap, Sparkles, Command, Plug, GitBranch, Send, Radio };

export default function WhiteboardCard({
  nodes,
  setNodes,
  edges,
  setEdges,
  activeNodeId,
  selectedNodeId,
  setSelectedNodeId,
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

  // Mouse move handler for canvas panning, node dragging, and wire previews
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
    if (
      e.target === canvasRef.current ||
      e.target.classList.contains('canvas-viewport') ||
      e.target.tagName === 'svg' ||
      e.target.classList.contains('canvas-bg') ||
      e.target.classList.contains('canvas-grid-figma')
    ) {
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
    setZoom((prevZoom) => Math.min(Math.max(prevZoom * zoomFactor, 0.4), 2.2));
  };

  const resetCamera = () => {
    setPan({ x: 0, y: 0 });
    setZoom(1);
  };

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
      const dropX = (e.clientX - rect.left - pan.x) / zoom - 135;
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
    if (nodes.find((node) => node.id === nodeId)?.category === 'source') return;
    setNodes((prev) => prev.filter((n) => n.id !== nodeId));
    setEdges((prev) => prev.filter((edge) => edge.source !== nodeId && edge.target !== nodeId));
    if (selectedNodeId === nodeId) setSelectedNodeId(null);
  };

  const getNodePortPos = (nodeId, isOutput) => {
    const node = nodes.find((n) => n.id === nodeId);
    if (!node) return { x: 0, y: 0 };
    return {
      x: isOutput ? node.x + 270 : node.x,
      y: node.y + 42
    };
  };

  return (
    <div className="w-full h-full relative overflow-hidden select-none flex-1">
      {/* Whiteboard Canvas Surface (White Background with Dot Grid) */}
      <div 
        ref={canvasRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onWheel={handleWheel}
        onDragOver={handleDragOver}
        onDrop={handleDrop}
        className={`w-full h-full relative overflow-hidden canvas-bg canvas-grid-figma bg-white cursor-grab ${
          isPanning ? 'cursor-grabbing' : ''
        }`}
      >
        {/* Pannable & Zoomable Viewport */}
        <div 
          style={{
            transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
            transformOrigin: '0 0'
          }}
          className="absolute inset-0 w-full h-full pointer-events-auto canvas-viewport"
        >
          {/* SVG Dotted Connection Wires Layer */}
          <svg className="absolute inset-0 w-[6000px] h-[6000px] pointer-events-none z-0">
            {edges.map((edge) => {
              const srcPos = getNodePortPos(edge.source, true);
              const tgtPos = getNodePortPos(edge.target, false);
              const deltaX = Math.abs(tgtPos.x - srcPos.x) * 0.5;
              const pathD = `M ${srcPos.x} ${srcPos.y} C ${srcPos.x + deltaX} ${srcPos.y}, ${tgtPos.x - deltaX} ${tgtPos.y}, ${tgtPos.x} ${tgtPos.y}`;

              const isEdgeActive = activeNodeId === edge.source || activeNodeId === edge.target;

              return (
                <g key={edge.id}>
                  <path
                    d={pathD}
                    fill="none"
                    stroke="#E2E8F0"
                    strokeWidth="4"
                    strokeDasharray="6 6"
                  />
                  <path
                    d={pathD}
                    fill="none"
                    stroke={isEdgeActive ? '#8B5CF6' : '#64748B'}
                    strokeWidth="2.5"
                    strokeDasharray="6 6"
                    className={isEdgeActive ? 'wire-path-active' : 'wire-path-figma'}
                  />
                </g>
              );
            })}

            {/* Connecting Wire Drag Preview */}
            {connectingPort && (
              <path
                d={`M ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).x} ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).y} Q ${mousePos.x} ${mousePos.y}, ${mousePos.x} ${mousePos.y}`}
                fill="none"
                stroke="#64748B"
                strokeWidth="3"
                strokeDasharray="6 6"
              />
            )}
          </svg>

          {/* Interactive Black Block Cards with Subtle Matching Black Port Connectors */}
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
                className={`figma-node-card ${
                  isRunning ? 'running' : ''
                } ${node.status === 'success' ? 'success' : ''} ${
                  isSelected ? 'selected' : ''
                } absolute z-10 p-4 font-sans text-left cursor-grab active:cursor-grabbing bg-zinc-950 border border-zinc-800 rounded-2xl shadow-xl transition-all hover:shadow-2xl text-zinc-100`}
              >
                {/* Subtle Left Input Connector Handle (Matching Black Theme) */}
                <div
                  onMouseUp={(e) => handlePortMouseUp(e, node.id, 'in', false)}
                  onMouseDown={(e) => handlePortMouseDown(e, node.id, 'in', false)}
                  className="group/port absolute -left-2 top-[34px] z-20 w-4 h-4 rounded-full border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 hover:border-zinc-500 flex items-center justify-center cursor-crosshair shadow-sm transition-transform hover:scale-125"
                  title="Input Port"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-zinc-400" />
                </div>

                {/* Subtle Right Output Connector Handle (Matching Black Theme) */}
                <div
                  onMouseUp={(e) => handlePortMouseUp(e, node.id, 'out', true)}
                  onMouseDown={(e) => handlePortMouseDown(e, node.id, 'out', true)}
                  className="group/port absolute -right-2 top-[38px] z-20 w-4 h-4 rounded-full border border-zinc-700 bg-zinc-900 hover:bg-zinc-800 hover:border-zinc-500 flex items-center justify-center cursor-crosshair shadow-sm transition-transform hover:scale-125"
                  title="Output Port"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-zinc-400" />
                </div>

                {/* Block Header */}
                <div className="flex items-center justify-between pb-3 mb-3 border-b border-zinc-800/80">
                  <div className="flex items-center gap-2.5 overflow-hidden">
                    <div
                      className="w-8 h-8 rounded-xl flex items-center justify-center text-white shrink-0 shadow-sm"
                      style={{ backgroundColor: catObj.color }}
                    >
                      <IconComp className="w-4.5 h-4.5" />
                    </div>
                    <div className="overflow-hidden">
                      <h4 className="text-xs font-bold text-white truncate font-sans">
                        {node.title}
                      </h4>
                      <p className="text-[10px] text-zinc-400 font-sans truncate">
                        {node.category === 'source' ? 'ENTRYPOINT TRIGGER' : `${catObj.name}`}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-1 shrink-0">
                    {isRunning && <Loader2 className="w-4 h-4 text-purple-400 animate-spin" />}
                    {node.status === 'success' && <CheckCircle2 className="w-4 h-4 text-emerald-400" />}
                    
                    {node.category !== 'source' && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setSelectedNodeId(node.id);
                        }}
                        className="p-1 rounded-lg hover:bg-zinc-800 text-zinc-400 hover:text-white transition"
                        title="Configure Block"
                      >
                        <Settings className="w-3.5 h-3.5" />
                      </button>
                    )}

                    {node.category !== 'source' && (
                      <button
                        onClick={(e) => handleDeleteNode(e, node.id)}
                        className="p-1 rounded-lg hover:bg-rose-950/60 text-zinc-400 hover:text-rose-400 transition"
                        title="Delete Block"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>

                {/* Config Preview Box */}
                <div className="bg-zinc-900/90 rounded-xl p-2.5 text-[11px] text-zinc-300 space-y-1 border border-zinc-800/80">
                  {Object.entries(node.config || {}).slice(0, 2).map(([k, v]) => (
                    <div key={k} className="flex justify-between items-center text-[10px]">
                      <span className="text-zinc-400 capitalize">{k}:</span>
                      <span className="font-semibold text-zinc-200 truncate max-w-[120px]">
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

      {/* Bottom-Right Camera Controls */}
      <div className="absolute bottom-6 right-6 z-20 flex items-center gap-1.5 bg-zinc-900/95 text-zinc-200 backdrop-blur-xl p-1.5 rounded-2xl border border-zinc-800 shadow-xl select-none">
        <button
          onClick={() => setZoom((z) => Math.min(z + 0.15, 2.2))}
          className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
          title="Zoom In"
        >
          <ZoomIn className="w-4 h-4" />
        </button>
        <span className="text-xs font-mono font-bold text-zinc-200 px-2 min-w-[48px] text-center">
          {Math.round(zoom * 100)}%
        </span>
        <button
          onClick={() => setZoom((z) => Math.max(z - 0.15, 0.4))}
          className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
          title="Zoom Out"
        >
          <ZoomOut className="w-4 h-4" />
        </button>
        <div className="h-4 w-px bg-zinc-800 mx-1" />
        <button
          onClick={resetCamera}
          className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
          title="Reset Zoom to 100%"
        >
          <Maximize2 className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}
