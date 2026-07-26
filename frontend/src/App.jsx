import React, { useState } from 'react';
import confetti from 'canvas-confetti';
import Header from './components/Header';
import PromptBar from './components/PromptBar';
import BlockPalette from './components/BlockPalette';
import ScratchCanvas from './components/ScratchCanvas';
import JacCodeViewer from './components/JacCodeViewer';
import ExecutionInspector from './components/ExecutionInspector';
import { INITIAL_NODES, INITIAL_EDGES, generateJacCode } from './data/blockDefinitions';
import { executeMacScriptViaTauri, isTauriEnvironment } from './services/tauriBridge';

export default function App() {
  const [nodes, setNodes] = useState(INITIAL_NODES);
  const [edges, setEdges] = useState(INITIAL_EDGES);

  const [activeNodeId, setActiveNodeId] = useState(null);
  const [selectedNodeId, setSelectedNodeId] = useState(null);
  const [editingNode, setEditingNode] = useState(null);

  const [showCodeView, setShowCodeView] = useState(true);
  const [isExecuting, setIsExecuting] = useState(false);
  const [executionSpeed, setExecutionSpeed] = useState('1x');
  const [isCompilingPrompt, setIsCompilingPrompt] = useState(false);

  const [logs, setLogs] = useState([
    {
      time: '11:00:00',
      prefix: '[Swirl Engine]',
      message: 'Jaclang v0.7.8 Visual Scratch Editor Ready. Graph walker initialized.',
      type: 'info'
    }
  ]);
  const [executionResults, setExecutionResults] = useState({});

  // Helper log emitter
  const addLog = (prefix, message, type = 'info') => {
    const timestamp = new Date().toLocaleTimeString('en-US', { hour12: false });
    setLogs((prev) => [...prev, { time: timestamp, prefix, message, type }]);
  };

  // Add block to canvas from sidebar or drop
  const handleAddNode = (blockDef, customX, customY) => {
    const newId = `node-${Date.now().toString().slice(-4)}`;
    const newNode = {
      id: newId,
      type: blockDef.type,
      title: blockDef.title,
      category: blockDef.category,
      jacNode: blockDef.jacNode,
      x: customX !== undefined ? customX : Math.floor(Math.random() * 200) + 200,
      y: customY !== undefined ? customY : Math.floor(Math.random() * 150) + 100,
      config: { ...blockDef.config },
      status: 'idle'
    };

    setNodes((prev) => [...prev, newNode]);

    // Connect to previous node if available
    if (nodes.length > 0) {
      const lastNode = nodes[nodes.length - 1];
      setEdges((prev) => [
        ...prev,
        { id: `edge-${lastNode.id}-${newId}`, source: lastNode.id, target: newId, sourcePort: 'out', targetPort: 'in' }
      ]);
    }

    addLog('[Canvas]', `Added Scratch block: ${blockDef.title} (${newId})`, 'info');
  };

  // Clear canvas
  const handleClearCanvas = () => {
    setNodes([]);
    setEdges([]);
    setSelectedNodeId(null);
    setActiveNodeId(null);
    setExecutionResults({});
    addLog('[Canvas]', 'Canvas cleared.', 'info');
  };

  // Select Preset Workflow
  const handleSelectPreset = (preset) => {
    setNodes(preset.nodes);
    setEdges(preset.edges);
    setSelectedNodeId(null);
    setActiveNodeId(null);
    setExecutionResults({});
    addLog('[Preset Loader]', `Loaded preset workflow: ${preset.name}`, 'success');
  };

  // Save Node Config
  const handleSaveNodeConfig = (nodeId, newTitle, newConfig) => {
    setNodes((prev) =>
      prev.map((n) => (n.id === nodeId ? { ...n, title: newTitle, config: newConfig } : n))
    );
    setEditingNode(null);
    addLog('[Node Config]', `Updated parameters for node (${nodeId})`, 'info');
  };

  // Prompt-to-Workflow AI Compiler Simulation
  const handleGenerateFromPrompt = (userPrompt) => {
    setIsCompilingPrompt(true);
    addLog('[PromptToWorkflowWalker]', `Translating prompt: "${userPrompt}"...`, 'info');

    setTimeout(() => {
      let generatedNodes = [];
      let generatedEdges = [];

      if (userPrompt.toLowerCase().includes('email') || userPrompt.toLowerCase().includes('mail')) {
        generatedNodes = [
          {
            id: 'node-p1',
            type: 'trigger_email',
            title: 'On Email Received',
            category: 'trigger',
            jacNode: 'TriggerBlock',
            x: 80,
            y: 140,
            config: { mailbox: 'Inbox', filterSubject: 'High Priority' },
            status: 'idle'
          },
          {
            id: 'node-p2',
            type: 'llm_summarize',
            title: 'LLM Summarizer',
            category: 'ai',
            jacNode: 'LLMTransformBlock',
            x: 440,
            y: 140,
            config: { prompt: 'Summarize email with Jac walker and extract action items.' },
            status: 'idle'
          },
          {
            id: 'node-p3',
            type: 'mac_notes',
            title: 'Apple Notes',
            category: 'mac',
            jacNode: 'MacAppBlock',
            x: 800,
            y: 80,
            config: { app: 'Notes', action: 'create_note', folder: 'AI Summaries' },
            status: 'idle'
          },
          {
            id: 'node-p4',
            type: 'mac_notification',
            title: 'Mac Notification',
            category: 'mac',
            jacNode: 'MacAppBlock',
            x: 800,
            y: 260,
            config: { app: 'System', action: 'display_notification', sound: 'Glass' },
            status: 'idle'
          }
        ];
        generatedEdges = [
          { id: 'edge-p1-p2', source: 'node-p1', target: 'node-p2', sourcePort: 'out', targetPort: 'in' },
          { id: 'edge-p2-p3', source: 'node-p2', target: 'node-p3', sourcePort: 'out', targetPort: 'in' },
          { id: 'edge-p2-p4', source: 'node-p2', target: 'node-p4', sourcePort: 'out', targetPort: 'in' }
        ];
      } else if (userPrompt.toLowerCase().includes('desktop') || userPrompt.toLowerCase().includes('finder')) {
        generatedNodes = [
          {
            id: 'node-p1',
            type: 'trigger_file',
            title: 'On File Created',
            category: 'trigger',
            jacNode: 'TriggerBlock',
            x: 80,
            y: 140,
            config: { watchPath: '~/Desktop' },
            status: 'idle'
          },
          {
            id: 'node-p2',
            type: 'mac_finder',
            title: 'Finder File Manager',
            category: 'mac',
            jacNode: 'MacAppBlock',
            x: 440,
            y: 140,
            config: { action: 'organize_by_extension', targetDirectory: '~/Desktop' },
            status: 'idle'
          },
          {
            id: 'node-p3',
            type: 'output_slack',
            title: 'Slack Webhook',
            category: 'output',
            jacNode: 'OutputBlock',
            x: 800,
            y: 140,
            config: { channel: '#desktop-organizer' },
            status: 'idle'
          }
        ];
        generatedEdges = [
          { id: 'edge-p1-p2', source: 'node-p1', target: 'node-p2', sourcePort: 'out', targetPort: 'in' },
          { id: 'edge-p2-p3', source: 'node-p2', target: 'node-p3', sourcePort: 'out', targetPort: 'in' }
        ];
      } else {
        // Generic fallback prompt workflow
        generatedNodes = [
          {
            id: 'node-p1',
            type: 'trigger_cron',
            title: 'Cron Schedule',
            category: 'trigger',
            jacNode: 'TriggerBlock',
            x: 80,
            y: 140,
            config: { cron: '0 * * * *' },
            status: 'idle'
          },
          {
            id: 'node-p2',
            type: 'mcp_fetch',
            title: 'MCP Web Scraper',
            category: 'mcp',
            jacNode: 'MCPToolBlock',
            x: 440,
            y: 140,
            config: { server: 'fetch-mcp', tool_name: 'fetch_url' },
            status: 'idle'
          },
          {
            id: 'node-p3',
            type: 'llm_summarize',
            title: 'LLM Summarizer',
            category: 'ai',
            jacNode: 'LLMTransformBlock',
            x: 800,
            y: 140,
            config: { prompt: userPrompt },
            status: 'idle'
          }
        ];
        generatedEdges = [
          { id: 'edge-p1-p2', source: 'node-p1', target: 'node-p2', sourcePort: 'out', targetPort: 'in' },
          { id: 'edge-p2-p3', source: 'node-p2', target: 'node-p3', sourcePort: 'out', targetPort: 'in' }
        ];
      }

      setNodes(generatedNodes);
      setEdges(generatedEdges);
      setIsCompilingPrompt(false);
      addLog('[PromptToWorkflowWalker]', `Compiled ${generatedNodes.length} visual Scratch blocks from intent!`, 'success');
    }, 900);
  };

  // Run Graph Walker Execution Simulation
  const handleRunWorkflow = async () => {
    if (nodes.length === 0 || isExecuting) return;

    setIsExecuting(true);
    setExecutionResults({});
    addLog('[WorkflowExecutorWalker]', 'Starting Jac Graph Traversal...', 'info');

    // Reset node statuses
    setNodes((prev) => prev.map((n) => ({ ...n, status: 'idle' })));

    const delayMs = executionSpeed === '2x' ? 400 : executionSpeed === 'Step' ? 1200 : 700;

    // Traverse nodes sequentially
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      setActiveNodeId(node.id);
      setNodes((prev) => prev.map((n) => (n.id === node.id ? { ...n, status: 'running' } : n)));

      addLog(
        `[Walker -> ${node.title}]`,
        `Executing node capability method: ${node.jacNode || 'WorkflowBlock'}.execute()`,
        'info'
      );

      await new Promise((resolve) => setTimeout(resolve, delayMs));

      // Simulate output per node type
      let mockOutput = {};
      if (node.category === 'trigger') {
        mockOutput = { triggerTime: new Date().toISOString(), status: 'Triggered' };
      } else if (node.category === 'ai') {
        mockOutput = {
          summary: 'Urgent: High priority action items extracted by Jac `by llm()` walker.',
          actionItems: ['Review JacHacks SF 2026 Submission', 'Test macOS AppleScript Note creation']
        };
      } else if (node.category === 'mac') {
        const tauriRes = await executeMacScriptViaTauri(node.config.app || 'Notes', node.config.action || 'create_note', node.config);
        mockOutput = { app: node.config.app || 'Notes', action: node.config.action || 'create_note', result: tauriRes.output || 'macOS AppleScript executed via Tauri Rust' };
      } else if (node.category === 'mcp') {
        mockOutput = { mcpServer: node.config.server, status: 200, content: 'Scraped 1.2KB markdown via stdio MCP bridge' };
      } else {
        mockOutput = { status: 'Executed', payload: node.config };
      }

      setExecutionResults((prev) => ({ ...prev, [node.id]: mockOutput }));
      setNodes((prev) => prev.map((n) => (n.id === node.id ? { ...n, status: 'success' } : n)));
      addLog(`[Walker -> ${node.title}]`, `Capability completed: SUCCESS`, 'success');
    }

    setActiveNodeId(null);
    setIsExecuting(false);
    addLog('[WorkflowExecutorWalker]', 'Graph Traversal completed successfully!', 'success');

    // Celebration Confetti
    try {
      confetti({
        particleCount: 80,
        spread: 70,
        origin: { y: 0.6 }
      });
    } catch (e) {
      // fallback
    }
  };

  // Export Jac Source File
  const handleExportJac = () => {
    const code = generateJacCode(nodes, edges);
    const blob = new Blob([code], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'workflow_agent.jac';
    link.click();
    URL.revokeObjectURL(url);
    addLog('[Exporter]', 'Downloaded generated workflow_agent.jac source file', 'success');
  };

  const selectedNode = nodes.find((n) => n.id === selectedNodeId);

  return (
    <div className="flex flex-col h-screen w-screen bg-slate-950 text-slate-100 overflow-hidden font-sans">
      {/* Header Bar */}
      <Header
        onRunWorkflow={handleRunWorkflow}
        isExecuting={isExecuting}
        executionSpeed={executionSpeed}
        setExecutionSpeed={setExecutionSpeed}
        onClearCanvas={handleClearCanvas}
        onSelectPreset={handleSelectPreset}
        showCodeView={showCodeView}
        setShowCodeView={setShowCodeView}
        onExportJac={handleExportJac}
        nodeCount={nodes.length}
        edgeCount={edges.length}
      />

      {/* Prompt Bar */}
      <PromptBar
        onGenerateFromPrompt={handleGenerateFromPrompt}
        isCompilingPrompt={isCompilingPrompt}
      />

      {/* Main Workspace Area */}
      <div className="flex-1 flex overflow-hidden relative">
        {/* Left Scratch Block Palette */}
        <BlockPalette onAddNode={handleAddNode} />

        {/* Center Canvas */}
        <ScratchCanvas
          nodes={nodes}
          setNodes={setNodes}
          edges={edges}
          setEdges={setEdges}
          activeNodeId={activeNodeId}
          selectedNodeId={selectedNodeId}
          setSelectedNodeId={setSelectedNodeId}
          onOpenConfigModal={(node) => setEditingNode(node)}
          onDropNewBlock={handleAddNode}
        />

        {/* Right Jac Code View Panel */}
        {showCodeView && (
          <JacCodeViewer
            nodes={nodes}
            edges={edges}
            onClose={() => setShowCodeView(false)}
            onExportJac={handleExportJac}
          />
        )}
      </div>

      {/* Bottom Execution Inspector Drawer */}
      <ExecutionInspector
        logs={logs}
        activeNode={selectedNode || nodes.find((n) => n.id === activeNodeId)}
        executionResults={executionResults}
        onClearLogs={() => setLogs([])}
      />

      {/* Node Config Modal */}
      {editingNode && (
        <NodeConfigModal
          node={editingNode}
          onSave={handleSaveNodeConfig}
          onClose={() => setEditingNode(null)}
        />
      )}
    </div>
  );
}
