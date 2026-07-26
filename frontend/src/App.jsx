import React, { useState } from 'react';
import Navbar from './components/Navbar';
import WhiteboardCard from './components/WhiteboardCard';
import CodeBlockPalette from './components/CodeBlockPalette';
import NodeConfigModal from './components/NodeConfigModal';
import JacCodeViewer from './components/JacCodeViewer';
import { INITIAL_NODES, INITIAL_EDGES } from './data/blockDefinitions';

export default function App() {
  const [nodes, setNodes] = useState(INITIAL_NODES);
  const [edges, setEdges] = useState(INITIAL_EDGES);
  const [isExecuting, setIsExecuting] = useState(false);
  const [activeNodeId, setActiveNodeId] = useState(null);
  const [selectedNodeId, setSelectedNodeId] = useState(null);
  const [editingNode, setEditingNode] = useState(null);
  const [showCodeView, setShowCodeView] = useState(false);

  // Add block to canvas
  const handleDropNewBlock = (blockDef, x, y) => {
    const newNode = {
      id: `node-${Date.now()}`,
      type: blockDef.type,
      title: blockDef.title,
      category: blockDef.category,
      x: x || 150,
      y: y || 150,
      config: { ...blockDef.config },
      status: 'idle'
    };
    setNodes((prev) => [...prev, newNode]);
    setSelectedNodeId(newNode.id);
  };

  const handleSaveNodeConfig = (nodeId, newTitle, newConfig) => {
    setNodes((prev) =>
      prev.map((n) => (n.id === nodeId ? { ...n, title: newTitle, config: newConfig } : n))
    );
    setEditingNode(null);
  };

  const handleRunWorkflow = () => {
    if (nodes.length === 0 || isExecuting) return;
    setIsExecuting(true);
    let idx = 0;

    const interval = setInterval(() => {
      if (idx < nodes.length) {
        const currentNode = nodes[idx];
        setActiveNodeId(currentNode.id);

        setNodes((prev) =>
          prev.map((n) => (n.id === currentNode.id ? { ...n, status: 'running' } : n))
        );

        setTimeout(() => {
          setNodes((prev) =>
            prev.map((n) => (n.id === currentNode.id ? { ...n, status: 'success' } : n))
          );
        }, 800);

        idx++;
      } else {
        clearInterval(interval);
        setTimeout(() => {
          setIsExecuting(false);
          setActiveNodeId(null);
        }, 1000);
      }
    }, 1200);
  };

  const handleClearCanvas = () => {
    setNodes([]);
    setEdges([]);
    setSelectedNodeId(null);
    setActiveNodeId(null);
  };

  return (
    <div className="h-screen w-screen bg-black text-neutral-100 relative overflow-hidden font-sans">
      {/* Floating Navbar */}
      <Navbar 
        isExecuting={isExecuting}
        showCodeView={showCodeView}
        setShowCodeView={setShowCodeView}
        onRunWorkflow={handleRunWorkflow}
        onClearCanvas={handleClearCanvas}
      />

      {/* Main Workspace: Whiteboard Grid Canvas + Right Code Block Palette */}
      <main className="h-full w-full relative">
        <WhiteboardCard 
          nodes={nodes}
          setNodes={setNodes}
          edges={edges}
          setEdges={setEdges}
          activeNodeId={activeNodeId}
          selectedNodeId={selectedNodeId}
          setSelectedNodeId={setSelectedNodeId}
          onOpenConfigModal={(node) => setEditingNode(node)}
          onDropNewBlock={handleDropNewBlock}
        />
        <CodeBlockPalette onAddBlock={(block) => handleDropNewBlock(block, 200, 200)} />

        {/* Jac Code Viewer Drawer */}
        {showCodeView && (
          <div className="fixed left-6 bottom-6 z-50 w-96 max-h-[60vh] rounded-3xl bg-neutral-950 border border-neutral-800 shadow-2xl p-4 overflow-y-auto">
            <JacCodeViewer nodes={nodes} edges={edges} onClose={() => setShowCodeView(false)} />
          </div>
        )}

        {/* Node Parameter Edit Modal */}
        {editingNode && (
          <NodeConfigModal 
            node={editingNode}
            onSave={handleSaveNodeConfig}
            onClose={() => setEditingNode(null)}
          />
        )}
      </main>
    </div>
  );
}


