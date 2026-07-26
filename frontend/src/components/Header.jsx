import React from 'react';
import { 
  Play, 
  RotateCcw, 
  Code, 
  Download, 
  Layers, 
  Zap, 
  Sparkles, 
  Sliders,
  CheckCircle2
} from 'lucide-react';
import { WORKFLOW_PRESETS } from '../data/blockDefinitions';

export default function Header({
  onRunWorkflow,
  isExecuting,
  executionSpeed,
  setExecutionSpeed,
  onClearCanvas,
  onSelectPreset,
  showCodeView,
  setShowCodeView,
  onExportJac,
  nodeCount,
  edgeCount
}) {
  return (
    <header className="h-16 glass-panel border-b border-white/10 px-6 flex items-center justify-between z-30 relative">
      {/* Brand & Jac Badge */}
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-purple-600 via-pink-500 to-amber-400 p-0.5 shadow-lg shadow-purple-500/20">
          <div className="w-full h-full bg-slate-950 rounded-[10px] flex items-center justify-center">
            <Zap className="w-5 h-5 text-amber-400 fill-amber-400/20 animate-pulse" />
          </div>
        </div>
        <div>
          <div className="flex items-center gap-2">
            <h1 className="font-display text-xl font-bold tracking-tight text-white">Swirl</h1>
            <span className="jac-badge text-xs uppercase tracking-wider">Jaclang v0.7.8</span>
          </div>
          <p className="text-xs text-slate-400 font-mono">Scratch Block Canvas • macOS MCP Control Center</p>
        </div>
      </div>

      {/* Center Controls: Preset Selector & Preset Loader */}
      <div className="flex items-center gap-3">
        <div className="relative group">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-slate-900/80 border border-white/10 text-xs text-slate-300 hover:border-purple-500/50 transition cursor-pointer">
            <Layers className="w-4 h-4 text-purple-400" />
            <span>Load Preset Workflow</span>
          </div>
          <div className="absolute top-full left-0 mt-2 w-72 glass-modal rounded-xl p-2 hidden group-hover:block z-50 animate-fade-in shadow-2xl border border-white/15">
            <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-400 px-3 py-1.5 mb-1">
              Sample Jac Workflows
            </div>
            {WORKFLOW_PRESETS.map((preset) => (
              <button
                key={preset.id}
                onClick={() => onSelectPreset(preset)}
                className="w-full text-left p-2.5 rounded-lg hover:bg-white/10 transition flex flex-col gap-1 text-xs group/btn"
              >
                <div className="font-medium text-slate-200 group-hover/btn:text-purple-300">
                  {preset.name}
                </div>
                <div className="text-[11px] text-slate-400 line-clamp-2">
                  {preset.description}
                </div>
              </button>
            ))}
          </div>
        </div>

        {/* Stats Pill */}
        <div className="hidden md:flex items-center gap-3 px-3 py-1.5 rounded-lg bg-slate-950/60 border border-white/5 font-mono text-xs text-slate-400">
          <span>Nodes: <strong className="text-purple-400">{nodeCount}</strong></span>
          <span className="text-slate-600">•</span>
          <span>Edges: <strong className="text-cyan-400">{edgeCount}</strong></span>
        </div>
      </div>

      {/* Right Controls: Run Execution, Speed, Jac Code View Toggle */}
      <div className="flex items-center gap-3">
        {/* Speed Toggle */}
        <div className="flex items-center bg-slate-900/80 rounded-lg p-0.5 border border-white/10 text-xs font-mono">
          {['1x', '2x', 'Step'].map((speed) => (
            <button
              key={speed}
              onClick={() => setExecutionSpeed(speed)}
              className={`px-2.5 py-1 rounded-md transition ${
                executionSpeed === speed 
                  ? 'bg-purple-600 text-white font-semibold shadow' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {speed}
            </button>
          ))}
        </div>

        {/* Run Walker Button */}
        <button
          onClick={onRunWorkflow}
          disabled={isExecuting || nodeCount === 0}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-xs transition shadow-lg ${
            isExecuting
              ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-wait'
              : nodeCount === 0
              ? 'bg-slate-800 text-slate-500 cursor-not-allowed border border-white/5'
              : 'bg-gradient-to-r from-purple-600 via-indigo-600 to-cyan-600 hover:from-purple-500 hover:to-cyan-500 text-white shadow-purple-600/30'
          }`}
        >
          {isExecuting ? (
            <>
              <Sparkles className="w-4 h-4 animate-spin text-amber-400" />
              <span>Walker Executing...</span>
            </>
          ) : (
            <>
              <Play className="w-4 h-4 fill-current" />
              <span>Run Walker</span>
            </>
          )}
        </button>

        {/* Code View Toggle */}
        <button
          onClick={() => setShowCodeView(!showCodeView)}
          className={`flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-mono border transition ${
            showCodeView
              ? 'bg-pink-600/20 text-pink-300 border-pink-500/50'
              : 'bg-slate-900/80 text-slate-300 border-white/10 hover:border-pink-500/40'
          }`}
          title="Toggle Jac Code Emitter Panel"
        >
          <Code className="w-4 h-4 text-pink-400" />
          <span className="hidden sm:inline">Jac Code</span>
        </button>

        {/* Export Jac Source Button */}
        <button
          onClick={onExportJac}
          className="p-2 rounded-lg bg-slate-900/80 text-slate-300 border border-white/10 hover:border-cyan-500/40 hover:text-cyan-300 transition"
          title="Export Generated .jac File"
        >
          <Download className="w-4 h-4" />
        </button>

        {/* Clear Canvas */}
        <button
          onClick={onClearCanvas}
          className="p-2 rounded-lg bg-slate-900/80 text-slate-400 border border-white/10 hover:border-rose-500/40 hover:text-rose-400 transition"
          title="Clear Canvas"
        >
          <RotateCcw className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
}
