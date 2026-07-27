import React, { useCallback, useEffect, useRef, useState } from 'react';
import Navbar from './components/Navbar';
import WhiteboardCard from './components/WhiteboardCard';
import CodeBlockPalette from './components/CodeBlockPalette';
import NodePropertiesPanel from './components/NodePropertiesPanel';
import JacCodeViewer from './components/JacCodeViewer';
import AIScreen from './components/AIScreen';
import WorkflowsScreen from './components/WorkflowsScreen';
import SaveWorkflowModal from './components/SaveWorkflowModal';
import ExecutionInspector from './components/ExecutionInspector';
import { INITIAL_NODES, INITIAL_EDGES } from './data/blockDefinitions';
import { suggestGeneratedWorkflowName } from './data/generatedProject';
import { normalizeWorkflow } from './data/workflowNormalization';
import {
  compileWorkflowPrompt,
  createWorkflow,
  generateJacSource,
  saveWorkflow,
  loadWorkflow,
  listWorkflows,
  deleteWorkflow,
  isTauriEnvironment,
  listenToWorkflowEvents,
  startWorkflow,
  stopWorkflow
} from './services/tauriBridge';

const AUTO_SAVE_DELAY_MS = 2000;

export default function App() {
  const initialWorkflow = normalizeWorkflow(INITIAL_NODES, INITIAL_EDGES);
  const [nodes, setNodes] = useState(initialWorkflow.nodes);
  const [edges, setEdges] = useState(initialWorkflow.edges);
  const [isExecuting, setIsExecuting] = useState(false);
  const [activeNodeId, setActiveNodeId] = useState(null);
  const [selectedNodeId, setSelectedNodeId] = useState(null);
  const [showCodeView, setShowCodeView] = useState(false);
  const [isCompilingPrompt, setIsCompilingPrompt] = useState(false);
  const [compileStatus, setCompileStatus] = useState({ type: 'idle', message: '' });
  const [activeRun, setActiveRun] = useState(null);
  const [isStopping, setIsStopping] = useState(false);
  const [logs, setLogs] = useState([]);
  const [executionResults, setExecutionResults] = useState({});
  const [generatedCode, setGeneratedCode] = useState(null);
  const [activeTab, setActiveTab] = useState('workflow');
  const [showLogsInspector, setShowLogsInspector] = useState(false);
  const terminalRunIds = useRef(new Set());

  const [editingWorkflow, setEditingWorkflow] = useState(false);
  const [currentWorkflowName, setCurrentWorkflowName] = useState(null);
  const [savedWorkflows, setSavedWorkflows] = useState([]);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState(null);
  const [showSaveModal, setShowSaveModal] = useState(false);

  const autoSaveTimerRef = useRef(null);
  const nodesRef = useRef(nodes);
  const edgesRef = useRef(edges);
  const currentNameRef = useRef(currentWorkflowName);
  const skipNextAutoSaveRef = useRef(false);

  nodesRef.current = nodes;
  edgesRef.current = edges;
  currentNameRef.current = currentWorkflowName;

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
      if (event.event === 'triggered' && event.nodeId) {
        setExecutionResults((prev) => ({ ...prev, [event.nodeId]: event.output }));
      }
      if (event.event === 'complete' && event.output) {
        setExecutionResults(event.output.results || {});
      }
      if (['complete', 'failed', 'stopped'].includes(event.event)) {
        if (event.runId) terminalRunIds.current.add(event.runId);
        setActiveRun((current) => {
          if (!current || !event.runId || current.runId === event.runId) {
            setIsExecuting(false);
            setIsStopping(false);
            setActiveNodeId(null);
            return null;
          }
          return current;
        });
      }
    }).then((cleanup) => { unlisten = cleanup; });
    return () => { if (unlisten) unlisten(); };
  }, []);

  const refreshWorkflowList = useCallback(async () => {
    if (!isTauriEnvironment()) return;
    try {
      const list = await listWorkflows();
      setSavedWorkflows(list || []);
    } catch (err) {
      console.error('[WorkflowManager] Failed to list workflows:', err);
    }
  }, []);

  useEffect(() => {
    if (!isTauriEnvironment()) return;
    (async () => {
      try {
        const list = await listWorkflows();
        if (!list || list.length === 0) {
          const workflow = normalizeWorkflow(INITIAL_NODES, INITIAL_EDGES);
          await saveWorkflow('Starter Workflow', workflow);
        }
      } catch (err) {
        console.error('[WorkflowManager] Failed to seed starter workflow:', err);
      }
    })();
  }, []);

  const performSave = useCallback(async (name, nodesToSave, edgesToSave) => {
    if (!isTauriEnvironment() || !name) return;
    setIsSaving(true);
    try {
      const workflow = normalizeWorkflow(nodesToSave, edgesToSave);
      await saveWorkflow(name, workflow);
      setHasUnsavedChanges(false);
      setSaveError(null);
      await refreshWorkflowList();
    } catch (err) {
      console.error('[WorkflowManager] Auto-save failed:', err);
      setSaveError(`Autosave failed: ${err}`);
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'save', message: `Save failed: ${err}`
      }]);
    } finally {
      setIsSaving(false);
    }
  }, [refreshWorkflowList, setLogs]);

  useEffect(() => {
    if (autoSaveTimerRef.current) clearTimeout(autoSaveTimerRef.current);
    if (skipNextAutoSaveRef.current) {
      skipNextAutoSaveRef.current = false;
      return;
    }
    if (!currentWorkflowName) return;
    setHasUnsavedChanges(true);
    autoSaveTimerRef.current = setTimeout(() => {
      performSave(currentNameRef.current, nodesRef.current, edgesRef.current);
    }, AUTO_SAVE_DELAY_MS);
    return () => { if (autoSaveTimerRef.current) clearTimeout(autoSaveTimerRef.current); };
  }, [nodes, edges, currentWorkflowName, performSave]);

  useEffect(() => {
    if (activeTab === 'workflow' && !editingWorkflow) refreshWorkflowList();
  }, [activeTab, editingWorkflow, refreshWorkflowList]);

  const handleNewWorkflow = () => {
    const fresh = normalizeWorkflow(INITIAL_NODES, INITIAL_EDGES);
    setNodes(fresh.nodes);
    setEdges(fresh.edges);
    setCurrentWorkflowName(null);
    setHasUnsavedChanges(false);
    setSaveError(null);
    setSelectedNodeId(null);
    setLogs([]);
    setExecutionResults({});
    setEditingWorkflow(true);
  };

  const handleLoadWorkflow = async (name) => {
    try {
      const record = await loadWorkflow(name);
      if (!record?.workflow) throw new Error('Workflow record is empty.');
      const loaded = normalizeWorkflow(record.workflow.nodes || [], record.workflow.edges || []);
      skipNextAutoSaveRef.current = true;
      setNodes(loaded.nodes);
      setEdges(loaded.edges);
      setCurrentWorkflowName(record.name);
      setHasUnsavedChanges(false);
      setSaveError(null);
      setSelectedNodeId(null);
      setLogs([]);
      setExecutionResults({});
      setEditingWorkflow(true);
    } catch (err) {
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'load', message: `Failed to load "${name}": ${err}`
      }]);
    }
  };

  const handleSaveWorkflowAs = async (name) => {
    setShowSaveModal(false);
    skipNextAutoSaveRef.current = true;
    setCurrentWorkflowName(name);
    await performSave(name, nodesRef.current, edgesRef.current);
  };

  const handleDeleteWorkflow = async (name) => {
    try {
      await deleteWorkflow(name);
      if (currentWorkflowName === name) {
        setCurrentWorkflowName(null);
        setHasUnsavedChanges(false);
      }
      await refreshWorkflowList();
    } catch (err) {
      console.error('[WorkflowManager] Delete failed:', err);
    }
  };

  const handleBackToManager = () => {
    setEditingWorkflow(false);
    setShowCodeView(false);
    setShowLogsInspector(false);
    setSelectedNodeId(null);
  };

  const handleDropNewBlock = (blockDef, x, y) => {
    const position = { x: x ?? 250, y: y ?? 180 };
    const newNode = {
      id: `node-${Date.now()}`,
      type: blockDef.type,
      title: blockDef.title,
      category: blockDef.category,
      jacNode: blockDef.jacNode || 'WorkflowBlock',
      x: position.x,
      y: position.y,
      position,
      customPrompt: '',
      config: { ...blockDef.config },
      status: 'idle'
    };
    setNodes((prev) => [...prev, newNode]);
    setSelectedNodeId(newNode.id);
  };

  const handleSaveNodeConfig = (nodeId, newTitle, newConfig, customPrompt) => {
    setNodes((prev) =>
      prev.map((n) => (n.id === nodeId ? {
        ...n,
        title: newTitle,
        config: newConfig,
        customPrompt: customPrompt ?? n.customPrompt
      } : n))
    );
  };

  const handleDuplicateNode = (node) => {
    const position = { x: node.x + 40, y: node.y + 40 };
    const newNode = {
      ...node,
      id: `node-${Date.now()}`,
      x: position.x,
      y: position.y,
      position,
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
      setNodes((prev) => prev.map((node) => ({ ...node, status: 'idle', output: {} })));
      const started = await startWorkflow(workflow);
      if (terminalRunIds.current.has(started.runId)) {
        terminalRunIds.current.delete(started.runId);
        setIsExecuting(false);
      } else {
        setActiveRun(started);
      }
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(),
        type: 'info',
        prefix: 'armed',
        message: `${started.runMode === 'continuous' ? 'Continuous' : 'One-time'} workflow ${started.runId} started.`
      }]);
    } catch (error) {
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'error', message: error.message
      }]);
      setIsExecuting(false);
      setActiveNodeId(null);
    }
  };

  const handleStopWorkflow = async () => {
    if (!activeRun?.runId || isStopping) return;
    setIsStopping(true);
    try {
      await stopWorkflow(activeRun.runId);
    } catch (error) {
      setIsStopping(false);
      setLogs((prev) => [...prev, {
        time: new Date().toLocaleTimeString(), type: 'error', prefix: 'stop', message: error.message
      }]);
    }
  };

  const handleGenerateFromPrompt = async (prompt) => {
    setIsCompilingPrompt(true);
    setCompileStatus({ type: 'compiling', message: 'Jac AI is building your new workflow project…' });
    try {
      const result = await compileWorkflowPrompt(prompt, true);
      if (!result?.nodes) throw new Error('Jac compiler returned no workflow graph.');
      const workflow = normalizeWorkflow(result.nodes, result.edges || []);
      const projectName = suggestGeneratedWorkflowName(prompt);
      const generatorLabel = result.source === 'llm' ? 'Jac LLM' : 'Jac fast compiler';

      if (autoSaveTimerRef.current) {
        clearTimeout(autoSaveTimerRef.current);
        autoSaveTimerRef.current = null;
      }
      currentNameRef.current = null;
      setCurrentWorkflowName(null);
      setHasUnsavedChanges(true);
      setSaveError(null);
      setNodes(workflow.nodes);
      setEdges(workflow.edges);
      setSelectedNodeId(null);
      setExecutionResults({});
      setGeneratedCode(null);
      setShowCodeView(false);
      setShowLogsInspector(false);
      setEditingWorkflow(true);
      setActiveTab('workflow');
      setLogs([{
        time: new Date().toLocaleTimeString(),
        type: 'success',
        prefix: 'compile',
        message: `Generated ${workflow.nodes.length} blocks with ${generatorLabel}.`
      }]);

      try {
        const record = await createWorkflow(projectName, workflow);
        skipNextAutoSaveRef.current = true;
        currentNameRef.current = record.name;
        setCurrentWorkflowName(record.name);
        setHasUnsavedChanges(false);
        setSavedWorkflows((current) => [
          record,
          ...current.filter((workflowRecord) => workflowRecord.name !== record.name)
        ]);
        setCompileStatus({
          type: 'success',
          message: `Created "${record.name}" with ${workflow.nodes.length} connected blocks using ${generatorLabel}.`
        });
        setLogs((current) => [...current, {
          time: new Date().toLocaleTimeString(),
          type: 'success',
          prefix: 'project',
          message: `Created new workflow project "${record.name}".`
        }]);
      } catch (saveFailure) {
        const message = saveFailure?.message || String(saveFailure);
        setSaveError(`New project could not be saved: ${message}`);
        setCompileStatus({
          type: 'error',
          message: `The workflow was generated, but its new project could not be saved: ${message}`
        });
        setLogs((current) => [...current, {
          time: new Date().toLocaleTimeString(),
          type: 'error',
          prefix: 'project',
          message: `Generated workflow is unsaved: ${message}`
        }]);
      }
    } catch (error) {
      setCompileStatus({
        type: 'error',
        message: error?.message || 'Jac could not generate a valid workflow. Check the provider configuration and try again.'
      });
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

  const isWorkflowTab = activeTab === 'workflow';
  const showEditor = isWorkflowTab && editingWorkflow;
  const showManager = isWorkflowTab && !editingWorkflow;

  return (
    <div className="h-screen w-screen flex flex-col relative overflow-hidden font-sans bg-black text-zinc-100 dark dark-theme">
      <Navbar
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        onRunWorkflow={handleRunWorkflow}
        onStopWorkflow={handleStopWorkflow}
        isExecuting={isExecuting}
        isStopping={isStopping}
        activeRunMode={activeRun?.runMode}
        showLogsInspector={showLogsInspector}
        onToggleLogs={() => setShowLogsInspector((prev) => !prev)}
        logsCount={logs.length}
        currentWorkflowName={currentWorkflowName}
        hasUnsavedChanges={hasUnsavedChanges}
        isSaving={isSaving}
        saveError={saveError}
        showBackButton={showEditor}
        onBack={handleBackToManager}
      />

      {showEditor ? (
        <div className="flex-1 flex w-full h-full overflow-hidden p-3 gap-3 bg-black">
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
      ) : showManager ? (
        <WorkflowsScreen
          savedWorkflows={savedWorkflows}
          currentWorkflowName={currentWorkflowName}
          onNew={handleNewWorkflow}
          onLoad={handleLoadWorkflow}
          onDelete={handleDeleteWorkflow}
          onRefresh={refreshWorkflowList}
        />
      ) : (
        <AIScreen 
          onGenerateFromPrompt={handleGenerateFromPrompt}
          isCompilingPrompt={isCompilingPrompt}
          onSwitchToWorkflow={() => setActiveTab('workflow')}
          compileStatus={compileStatus}
        />
      )}

      {showEditor && showCodeView && (
        <JacCodeViewer
          nodes={nodes}
          edges={edges}
          jacCode={generatedCode}
          onClose={() => handleCodeView(false)}
        />
      )}

      {showEditor && (
        <ExecutionInspector
          isOpen={showLogsInspector}
          onClose={() => setShowLogsInspector(false)}
          logs={logs}
          activeNode={selectedNode || nodes.find((node) => node.id === activeNodeId)}
          executionResults={executionResults}
          onClearLogs={() => { setLogs([]); setExecutionResults({}); }}
        />
      )}

      {showSaveModal && (
        <SaveWorkflowModal
          onSave={handleSaveWorkflowAs}
          onClose={() => setShowSaveModal(false)}
          existingNames={savedWorkflows.map((w) => w.name)}
        />
      )}
    </div>
  );
}
