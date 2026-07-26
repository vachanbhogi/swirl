import React, { useEffect, useState } from 'react';
import Navbar from './components/Navbar';
import WhiteboardCard from './components/WhiteboardCard';
import CodeBlockPalette from './components/CodeBlockPalette';
import NodePropertiesPanel from './components/NodePropertiesPanel';
import JacCodeViewer from './components/JacCodeViewer';
import AIScreen from './components/AIScreen';
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
  const [showCodeView, setShowCodeView] = useState(false);
  const [isCompilingPrompt, setIsCompilingPrompt] = useState(false);
  const [logs, setLogs] = useState([]);
  const [executionResults, setExecutionResults] = useState({});
  const [generatedCode, setGeneratedCode] = useState(null);
  const [activeTab, setActiveTab] = useState('workflow'); // 'workflow' | 'ai'
  const [showLogsInspector, setShowLogsInspector] = useState(false);

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

  const handleDropNewBlock = (blockDef, x, y) => {
    const newNode = {
      id: `node-${Date.now()}`,
      type: blockDef.type,
      title: blockDef.title,
      category: blockDef.category,
      jacNode: blockDef.jacNode || 'WorkflowBlock',
      x: x || 250,
      y: y || 180,
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
  };

  const handleDuplicateNode = (node) => {
    const newNode = {
      ...node,
      id: `node-${Date.now()}`,
      x: node.x + 40,
      y: node.y + 40,
      status: 'idle'
    };
    setNodes((prev) => [...prev, newNode]);
    setSelectedNodeId(newNode.id);
  };

  const handleDeleteNode = (nodeId) => {
    if (nodes.find((node) => node.id === nodeId)?.category === 'source') return;
    setNodes((prev) => prev.filter((n) => n.id !== nodeId));
    setEdges((prev) => prev.filter((edge) => edge.source !== nodeId && edge.target !== nodeId));
    if (selectedNodeId === nodeId) setSelectedNodeId(null);
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
      setActiveTab('workflow');
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

  const isWorkflowView = activeTab === 'workflow';

  return (
    <div className="h-screen w-screen flex flex-col relative overflow-hidden font-sans bg-black text-zinc-100 dark dark-theme">
      {/* Top Navbar — visible on both screens for tab switching */}
      <Navbar 
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        onRunWorkflow={handleRunWorkflow}
        isExecuting={isExecuting}
        showLogsInspector={showLogsInspector}
        onToggleLogs={() => setShowLogsInspector((prev) => !prev)}
        logsCount={logs.length}
      />

      {/* Main Workspace Layout */}
      {isWorkflowView ? (
        /* Visual Workflow Canvas Screen */
        <div className="flex-1 flex w-full h-full overflow-hidden p-3 gap-3 bg-black">
          {/* Center Canvas Area */}
          <main className="flex-1 h-full relative flex flex-col rounded-2xl overflow-hidden border border-zinc-800 bg-black shadow-xl">
            <WhiteboardCard 
              nodes={nodes}
              setNodes={setNodes}
              edges={edges}
              setEdges={setEdges}
              activeNodeId={activeNodeId}
              selectedNodeId={selectedNodeId}
              setSelectedNodeId={setSelectedNodeId}
              onDropNewBlock={handleDropNewBlock}
              isDarkMode={false}
              showLogsInspector={showLogsInspector}
              onToggleLogs={() => setShowLogsInspector((prev) => !prev)}
              logsCount={logs.length}
            />
          </main>

          {/* Right Side: Building Blocks Palette / Node Inspector Panel */}
          <div className="h-full rounded-2xl overflow-hidden border border-zinc-800 shadow-sm shrink-0 bg-zinc-950">
            {selectedNode ? (
              <NodePropertiesPanel 
                selectedNode={selectedNode}
                onSaveNodeConfig={handleSaveNodeConfig}
                onDeleteNode={handleDeleteNode}
                onDuplicateNode={handleDuplicateNode}
                onClose={() => setSelectedNodeId(null)}
                totalNodes={nodes.length}
                totalEdges={edges.length}
                onRunWorkflow={handleRunWorkflow}
              />
            ) : (
              <CodeBlockPalette onAddBlock={(block) => handleDropNewBlock(block, 260, 200)} />
            )}
          </div>
        </div>
      ) : (
        /* Full Standalone AI Screen — no workflow chrome */
        <AIScreen 
          onGenerateFromPrompt={handleGenerateFromPrompt}
          isCompilingPrompt={isCompilingPrompt}
        />
      )}

      {/* Jac Code Drawer — workflow only */}
      {isWorkflowView && showCodeView && (
        <JacCodeViewer 
          nodes={nodes} 
          edges={edges} 
          jacCode={generatedCode} 
          onClose={() => handleCodeView(false)} 
        />
      )}

      {/* Floating Activity Inspector Overlay — workflow only */}
      {isWorkflowView && (
        <ExecutionInspector
          isOpen={showLogsInspector}
          onClose={() => setShowLogsInspector(false)}
          logs={logs}
          activeNode={selectedNode || nodes.find((node) => node.id === activeNodeId)}
          executionResults={executionResults}
          onClearLogs={() => { setLogs([]); setExecutionResults({}); }}
        />
      )}
    </div>
  );
}
