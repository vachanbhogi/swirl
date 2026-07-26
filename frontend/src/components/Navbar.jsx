import React from 'react';
import { Play, Layers, Sparkles, Square, Terminal } from 'lucide-react';

export default function Navbar({
  activeTab = 'workflow',
  setActiveTab,
  onRunWorkflow,
  onStopWorkflow,
  isExecuting,
  isStopping,
  activeRunMode,
  showLogsInspector,
  onToggleLogs,
  logsCount = 0
}) {
  return (
    <header className="h-14 w-full bg-[#0A0D14]/95 border-b border-zinc-800/80 px-6 flex items-center justify-between z-40 select-none shrink-0 font-sans">
      {/* Left: Empty Space */}
      <div className="w-16" />

      {/* Center: Minimal Segmented Tabs */}
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

        {isExecuting ? (
          <button
            onClick={onStopWorkflow}
            disabled={isStopping}
            className="flex items-center gap-2 px-4 py-1.5 rounded-xl text-xs font-bold transition font-sans bg-rose-950/60 text-rose-200 border border-rose-800/70 hover:bg-rose-900/60 disabled:cursor-wait disabled:opacity-60"
          >
            <Square className="w-3.5 h-3.5 fill-current" />
            <span>{isStopping ? 'Stopping…' : `Stop ${activeRunMode === 'continuous' ? 'Listener' : 'Workflow'}`}</span>
          </button>
        ) : (
          <button
            onClick={onRunWorkflow}
            className="flex items-center gap-2 px-4 py-1.5 rounded-xl text-xs font-bold transition font-sans bg-white text-zinc-900 hover:bg-zinc-200 shadow-sm active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
          >
            <Play className="w-3.5 h-3.5 fill-current" />
            <span>Run Workflow</span>
          </button>
        )}
      </div>
    </header>
  );
}
