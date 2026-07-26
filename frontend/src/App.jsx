import React, { useEffect, useState } from 'react';
import Navbar from './components/Navbar';
import WhiteboardCard from './components/WhiteboardCard';
import CodeBlockPalette from './components/CodeBlockPalette';
import NodeConfigModal from './components/NodeConfigModal';
import JacCodeViewer from './components/JacCodeViewer';
import PromptBar from './components/PromptBar';
import ExecutionInspector from './components/ExecutionInspector';
import { INITIAL_NODES, INITIAL_EDGES } from './data/blockDefinitions';
import { normalizeWorkflow } from './data/workflowNormalization';
import {
  compileWorkflowPrompt,
  executeWorkflow,
  generateJacSource,
  isTauriEnvironment,
  listenToWorkflowEvents
} from './services/tauriBridge';

export default function App() {
  const initialWorkflow = normalizeWorkflow(INITIAL_NODES, INITIAL_EDGES);
  const [nodes, setNodes] = useState(initialWorkflow.nodes);
  const [edges, setEdges] = useState(initialWorkflow.edges);
  const [isExecuting, setIsExecuting] = useState(false);
  const [activeNodeId, setActiveNodeId] = useState(null);
  const [selectedNodeId, setSelectedNodeId] = useState(null);
  const [editingNode, setEditingNode] = useState(null);
  const [showCodeView, setShowCodeView] = useState(false);
  const [isCompilingPrompt, setIsCompilingPrompt] = useState(false);
  const [logs, setLogs] = useState([]);
  const [executionResults, setExecutionResults] = useState({});
  const [generatedCode, setGeneratedCode] = useState(null);

  useEffect(() => {
    let unlisten;
    listenToWorkflowEvents((event) => {
      const time = new Date().toLocaleTimeString();
      setLogs((prev) => [...prev, {
        time,
        type: event.status === 'error' ? 'error' : event.status === 'success' ? 'success' : 'info',
        prefix: event.event,
        message: event.message || event.title || 'Workflow event received'
      }]);

      if (event.nodeId) {
        setActiveNodeId(event.nodeId);
        setNodes((prev) => prev.map((node) => (
          node.id === event.nodeId ? { ...node, status: event.status || node.status, output: event.output || node.output } : node
        )));
      }
      if (event.event === 'node_complete' && event.nodeId) {
        setExecutionResults((prev) => ({ ...prev, [event.nodeId]: event.output }));
      }
    }).then((cleanup) => { unlisten = cleanup; });
    return () => { if (unlisten) unlisten(); };
  }, []);

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

  const handleRunWorkflow = async () => {
    if (nodes.length === 0 || isExecuting) return;
    setIsExecuting(true);
    setExecutionResults({});
    setLogs([]);
    try {
      if (!isTauriEnvironment()) {
        throw new Error('Run the Tauri desktop app to execute native workflows.');
      }
      const workflow = normalizeWorkflow(nodes, edges);
      setNodes(workflow.nodes);
      setEdges(workflow.edges);
      const summary = await executeWorkflow(workflow);
      setExecutionResults(summary.results || {});
      setNodes((prev) => prev.map((node) => (
        summary.completedNodeIds?.includes(node.id) ? { ...node, status: 'success' } : node
      )));
    } catch (error) {
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'error', message: error.message
      }]);
    } finally {
      setIsExecuting(false);
      setActiveNodeId(null);
    }
  };

  const handleGenerateFromPrompt = async (prompt) => {
    setIsCompilingPrompt(true);
    try {
      const result = await compileWorkflowPrompt(prompt, true);
      if (!result?.nodes) throw new Error('Jac compiler returned no workflow graph.');
      const workflow = normalizeWorkflow(result.nodes, result.edges || []);
      setNodes(workflow.nodes);
      setEdges(workflow.edges);
      setSelectedNodeId(null);
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'success', prefix: 'compile', message: `Generated ${workflow.nodes.length} blocks from Jac LLM.`
      }]);
    } catch (error) {
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'compile', message: error.message
      }]);
    } finally {
      setIsCompilingPrompt(false);
    }
  };

  const handleCodeView = async (nextValue) => {
    setShowCodeView(nextValue);
    if (nextValue && isTauriEnvironment()) {
        try {
          const workflow = normalizeWorkflow(nodes, edges);
          setNodes(workflow.nodes);
          setEdges(workflow.edges);
          setGeneratedCode(await generateJacSource(workflow));
        } catch (error) {
        setLogs((prev) => [...prev, { time: new Date().toLocaleTimeString(), type: 'error', prefix: 'code', message: error.message }]);
      }
    }
  };

  const selectedNode = nodes.find((node) => node.id === selectedNodeId) || null;

  const handleClearCanvas = () => {
    setNodes(initialWorkflow.nodes);
    setEdges(initialWorkflow.edges);
    setSelectedNodeId(null);
    setActiveNodeId(null);
  };

  return (
    <div className="h-screen w-screen bg-black text-neutral-100 relative overflow-hidden font-sans">
      {/* Floating Navbar */}
      <Navbar 
        isExecuting={isExecuting}
        showCodeView={showCodeView}
        setShowCodeView={handleCodeView}
        onRunWorkflow={handleRunWorkflow}
        onClearCanvas={handleClearCanvas}
      />

      {/* Main Workspace: Whiteboard Grid Canvas + Right Code Block Palette */}
      <main className="h-full w-full relative">
        <div className="fixed left-6 right-80 top-20 z-30">
          <PromptBar onGenerateFromPrompt={handleGenerateFromPrompt} isCompilingPrompt={isCompilingPrompt} />
        </div>
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
            <JacCodeViewer nodes={nodes} edges={edges} jacCode={generatedCode} onClose={() => handleCodeView(false)} />
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
        <div className="fixed left-6 right-80 bottom-0 z-30">
          <ExecutionInspector
            logs={logs}
            activeNode={selectedNode || nodes.find((node) => node.id === activeNodeId)}
            executionResults={executionResults}
            onClearLogs={() => { setLogs([]); setExecutionResults({}); }}
          />
        </div>
      </main>
    </div>
  );
}
