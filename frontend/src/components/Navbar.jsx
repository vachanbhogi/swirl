import React from 'react';
import { Play, Layers, Sparkles, Terminal, ArrowLeft, Loader2, CircleAlert } from 'lucide-react';

export default function Navbar({
  activeTab = 'workflow',
  setActiveTab,
  onRunWorkflow,
  isExecuting,
  showLogsInspector,
  onToggleLogs,
  logsCount = 0,
  currentWorkflowName,
  hasUnsavedChanges,
  isSaving,
  saveError,
  showBackButton,
  onBack
}) {
  const displayName = currentWorkflowName || 'Untitled';

  return (
    <header className="h-14 w-full bg-[#0A0D14]/95 border-b border-zinc-800/80 px-6 flex items-center justify-between z-40 select-none shrink-0 font-sans">
      {/* Left: Back button when editing, or workflow name */}
      <div className="flex items-center gap-2 min-w-[160px] mt-5">
        {showBackButton ? (
          <>
            <button
              onClick={onBack}
              className="flex items-center gap-1.5 px-2 py-1.5 rounded-xl text-xs font-semibold text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
              title="Back to Workflows"
            >
              <ArrowLeft className="w-4 h-4" />
            </button>
            <span className="text-xs font-semibold text-zinc-300 truncate max-w-[180px]" title={currentWorkflowName || 'Unsaved workflow'}>
              {displayName}
            </span>
            {saveError ? (
              <CircleAlert className="w-3.5 h-3.5 text-red-400 shrink-0" title={saveError} />
            ) : isSaving ? (
              <Loader2 className="w-3 h-3 text-zinc-500 animate-spin shrink-0" />
            ) : hasUnsavedChanges ? (
              <span className="w-2 h-2 rounded-full bg-amber-400 shrink-0" title="Unsaved changes" />
            ) : currentWorkflowName ? (
              <span className="w-2 h-2 rounded-full bg-emerald-400 shrink-0" title="Saved" />
            ) : null}
          </>
        ) : (
          <div className="w-16" />
        )}
      </div>

      {/* Center: Segmented Tabs */}
      <div className="flex items-center gap-1 p-1 bg-zinc-900/90 rounded-2xl border border-zinc-800">
        <button
          onClick={() => setActiveTab && setActiveTab('workflow')}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-xl text-xs font-semibold transition font-sans ${
            activeTab === 'workflow'
              ? 'bg-zinc-800 text-white shadow-sm border border-zinc-700'
              : 'text-zinc-400 hover:text-zinc-200'
          }`}
        >
          <Layers className="w-3.5 h-3.5" />
          <span>Workflow</span>
        </button>

        <button
          onClick={() => setActiveTab && setActiveTab('ai')}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-xl text-xs font-semibold transition font-sans ${
            activeTab === 'ai'
              ? 'bg-zinc-800 text-white shadow-sm border border-zinc-700'
              : 'text-zinc-400 hover:text-zinc-200'
          }`}
        >
          <Sparkles className="w-3.5 h-3.5" />
          <span>AI Builder</span>
        </button>
      </div>

      {/* Right: Actions */}
      <div className="flex items-center gap-3">
        <button
          onClick={onToggleLogs}
          className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-mono font-semibold border transition ${
            showLogsInspector
              ? 'bg-purple-950/80 text-purple-300 border-purple-700 shadow-sm'
              : 'bg-zinc-900 text-zinc-300 border-zinc-800 hover:text-white hover:border-zinc-700'
          }`}
          title="Toggle Walker Logs Inspector"
        >
          <Terminal className="w-3.5 h-3.5 text-purple-400" />
          <span>Logs ({logsCount})</span>
        </button>

        <button
          onClick={onRunWorkflow}
          disabled={isExecuting}
          className={`flex items-center gap-2 px-4 py-1.5 rounded-xl text-xs font-bold transition font-sans ${
            isExecuting
              ? 'bg-zinc-800 text-zinc-500 cursor-wait'
              : 'bg-white text-zinc-900 hover:bg-zinc-200 shadow-sm active:scale-95'
          }`}
        >
          <Play className={`w-3.5 h-3.5 fill-current ${isExecuting ? 'animate-spin' : ''}`} />
          <span>{isExecuting ? 'Executing...' : 'Run Workflow'}</span>
        </button>
      </div>
    </header>
  );
}
