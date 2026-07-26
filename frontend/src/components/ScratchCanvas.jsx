import React, { useState, useRef, useEffect } from 'react';
import { 
  Zap, 
  Sparkles, 
  Command, 
  Plug, 
  GitBranch, 
  Send, 
  Trash2, 
  Settings, 
  CheckCircle2, 
  AlertCircle, 
  Loader2,
  X
} from 'lucide-react';
import { BLOCK_CATEGORIES } from '../data/blockDefinitions';

const ICON_MAP = { Zap, Sparkles, Command, Plug, GitBranch, Send };

export default function ScratchCanvas({
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
  const canvasRef = useRef(null);
  const [draggingNodeId, setDraggingNodeId] = useState(null);
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
  const [connectingPort, setConnectingPort] = useState(null); // { nodeId, portName, isOutput }
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });

  // Mouse Move Handler for node drag & connecting wire preview
  const handleMouseMove = (e) => {
    if (!canvasRef.current) return;
    const rect = canvasRef.current.getBoundingClientRect();
    const currentX = e.clientX - rect.left;
    const currentY = e.clientY - rect.top;

    setMousePos({ x: currentX, y: currentY });

    if (draggingNodeId) {
      setNodes((prevNodes) =>
        prevNodes.map((n) =>
          n.id === draggingNodeId
            ? { ...n, position: { x: Math.max(20, currentX - dragOffset.x), y: Math.max(20, currentY - dragOffset.y) } }
            : n
        )
      );
    }
  };

  const handleMouseUp = () => {
    setDraggingNodeId(null);
    setConnectingPort(null);
  };

  // Drag over & Drop new block from sidebar palette
  const handleDragOver = (e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'copy';
  };

  const handleDrop = (e) => {
    e.preventDefault();
    const rawData = e.dataTransfer.getData('application/swirl-block');
    if (!rawData) return;

    try {
      const blockDef = JSON.parse(rawData);
      const rect = canvasRef.current.getBoundingClientRect();
      const dropX = e.clientX - rect.left - 100;
      const dropY = e.clientY - rect.top - 40;

      onDropNewBlock(blockDef, dropX, dropY);
    } catch (err) {
      console.error('Failed to parse dropped block:', err);
    }
  };

  const handleNodeMouseDown = (e, node) => {
    e.stopPropagation();
    setSelectedNodeId(node.id);
    setDraggingNodeId(node.id);

    const rect = canvasRef.current.getBoundingClientRect();
    setDragOffset({
      x: e.clientX - rect.left - node.position.x,
      y: e.clientY - rect.top - node.position.y
    });
  };

  // Start port connection wire
  const handlePortMouseDown = (e, nodeId, portName, isOutput) => {
    e.stopPropagation();
    setConnectingPort({ nodeId, portName, isOutput });
  };

  // Complete port connection wire
  const handlePortMouseUp = (e, targetNodeId, targetPortName, isTargetOutput) => {
    e.stopPropagation();
    if (!connectingPort) return;

    if (connectingPort.nodeId !== targetNodeId && connectingPort.isOutput !== isTargetOutput) {
      const sourceId = connectingPort.isOutput ? connectingPort.nodeId : targetNodeId;
      const targetId = connectingPort.isOutput ? targetNodeId : connectingPort.nodeId;
      const sourcePort = connectingPort.isOutput ? connectingPort.portName : targetPortName;
      const targetPort = connectingPort.isOutput ? targetPortName : connectingPort.portName;

      const newEdgeId = `edge-${sourceId}-${targetId}`;

      // Check duplicate
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

  // Helper to compute node center port positions for SVG bezier curve rendering
  const getNodePortPos = (nodeId, isOutput) => {
    const node = nodes.find((n) => n.id === nodeId);
    if (!node) return { x: 0, y: 0 };
    return {
      x: isOutput ? node.position.x + 280 : node.position.x,
      y: node.position.y + 45
    };
  };

  return (
    <main
      ref={canvasRef}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
      onClick={() => setSelectedNodeId(null)}
      className="flex-1 relative canvas-grid overflow-hidden h-[calc(100vh-8rem)] select-none"
    >
      {/* SVG Edges Layer */}
      <svg className="absolute inset-0 w-full h-full pointer-events-none z-0">
        <defs>
          <linearGradient id="edge-grad" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#8B5CF6" />
            <stop offset="50%" stopColor="#38BDF8" />
            <stop offset="100%" stopColor="#34D399" />
          </linearGradient>
        </defs>

        {/* Existing Wire Edges */}
        {edges.map((edge) => {
          const srcPos = getNodePortPos(edge.source, true);
          const tgtPos = getNodePortPos(edge.target, false);

          const isWireActive = activeNodeId === edge.source || activeNodeId === edge.target;
          const deltaX = Math.abs(tgtPos.x - srcPos.x) * 0.5;
          const pathD = `M ${srcPos.x} ${srcPos.y} C ${srcPos.x + deltaX} ${srcPos.y}, ${tgtPos.x - deltaX} ${tgtPos.y}, ${tgtPos.x} ${tgtPos.y}`;

          return (
            <g key={edge.id}>
              {/* Outer Glow */}
              <path
                d={pathD}
                fill="none"
                stroke={isWireActive ? '#10B981' : 'rgba(139, 92, 246, 0.4)'}
                strokeWidth={isWireActive ? '6' : '3'}
                opacity={isWireActive ? 0.8 : 0.6}
              />
              {/* Core Wire */}
              <path
                d={pathD}
                fill="none"
                stroke="url(#edge-grad)"
                strokeWidth="2.5"
                className={isWireActive ? 'wire-path-active' : 'wire-path'}
              />
            </g>
          );
        })}

        {/* Live Connecting Wire Drag Preview */}
        {connectingPort && (
          <path
            d={`M ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).x} ${getNodePortPos(connectingPort.nodeId, connectingPort.isOutput).y} Q ${mousePos.x} ${mousePos.y}, ${mousePos.x} ${mousePos.y}`}
            fill="none"
            stroke="#38BDF8"
            strokeWidth="3"
            strokeDasharray="6"
          />
        )}
      </svg>

      {/* Nodes Layer */}
      {nodes.map((node) => {
        const catObj = BLOCK_CATEGORIES.find((c) => c.id === node.category) || BLOCK_CATEGORIES[0];
        const IconComp = ICON_MAP[catObj.icon] || Zap;

        const isRunning = activeNodeId === node.id;
        const isSelected = selectedNodeId === node.id;
        const isOutputOnly = node.category === 'trigger' || node.category === 'source';

        return (
          <div
            key={node.id}
            onMouseDown={(e) => handleNodeMouseDown(e, node)}
            style={{ left: `${node.position.x}px`, top: `${node.position.y}px`, width: '280px' }}
            className={`scratch-block block-cat-${node.category} ${
              isRunning ? 'node-running' : ''
            } ${node.status === 'success' ? 'node-success' : ''} ${
              isSelected ? 'selected' : ''
            } z-10 p-3.5 rounded-xl border relative`}
          >
            {!isOutputOnly && (
              <div
                onMouseUp={(e) => handlePortMouseUp(e, node.id, 'in', false)}
                onMouseDown={(e) => handlePortMouseDown(e, node.id, 'in', false)}
                className="block-port absolute -left-2 top-[38px] z-20 shadow-md"
                title="Input Connect Port (accepts multiple connections)"
              />
            )}

            {/* Output Port (Right Side) */}
            <div
              onMouseUp={(e) => handlePortMouseUp(e, node.id, 'out', true)}
              onMouseDown={(e) => handlePortMouseDown(e, node.id, 'out', true)}
              className="block-port absolute -right-2 top-[38px] z-20 shadow-md"
              title={node.category === 'trigger' ? 'Trigger output' : 'Output Connect Port'}
            />

            {/* Block Header */}
            <div className="flex items-center justify-between gap-2 mb-2">
              <div className="flex items-center gap-2 overflow-hidden">
                <div
                  className="w-7 h-7 rounded-lg flex items-center justify-center text-white shrink-0 shadow"
                  style={{ backgroundColor: catObj.color }}
                >
                  <IconComp className="w-4 h-4" />
                </div>
                <div className="overflow-hidden">
                  <h4 className="text-xs font-bold text-slate-100 truncate">
                    {node.title}
                  </h4>
                  <p className="text-[10px] text-slate-400 font-mono truncate">
                    {node.category.toUpperCase()} • {node.type}
                  </p>
                </div>
              </div>

              {/* Status & Actions */}
              <div className="flex items-center gap-1.5 shrink-0">
                {isRunning && (
                  <Loader2 className="w-4 h-4 text-amber-400 animate-spin" />
                )}
                {node.status === 'success' && (
                  <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                )}

                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onOpenConfigModal(node);
                  }}
                  className="p-1 rounded-md bg-white/10 hover:bg-white/20 text-slate-300 hover:text-white transition"
                  title="Configure Parameters"
                >
                  <Settings className="w-3.5 h-3.5" />
                </button>

                <button
                  onClick={(e) => handleDeleteNode(e, node.id)}
                  className="p-1 rounded-md bg-white/10 hover:bg-rose-500/30 text-slate-400 hover:text-rose-300 transition"
                  title="Delete Block"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            {/* Config Parameter Snippet */}
            <div className="bg-slate-950/60 rounded-lg p-2 text-[11px] font-mono text-slate-300 border border-white/5 space-y-1">
              {Object.entries(node.config || {}).slice(0, 2).map(([key, val]) => (
                <div key={key} className="flex items-center justify-between text-[10px]">
                  <span className="text-slate-400">{key}:</span>
                  <span className="text-amber-300 font-semibold truncate max-w-[120px]">
                    {typeof val === 'object' ? JSON.stringify(val) : String(val)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        );
      })}

      {/* Empty State Banner */}
      {nodes.length === 0 && (
        <div className="absolute inset-0 flex flex-col items-center justify-center text-center p-6 text-slate-500 font-sans pointer-events-none">
          <div className="w-16 h-16 rounded-2xl bg-purple-600/10 border border-purple-500/20 flex items-center justify-center mb-4">
            <Sparkles className="w-8 h-8 text-purple-400 animate-pulse" />
          </div>
          <h3 className="text-base font-semibold text-slate-300 mb-1">
            Visual Canvas is Empty
          </h3>
          <p className="text-xs text-slate-500 max-w-sm">
            Drag Scratch blocks from the left palette or type a prompt in the top bar to auto-generate a Jac agent graph.
          </p>
        </div>
      )}
    </main>
  );
}
