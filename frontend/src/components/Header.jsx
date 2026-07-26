import React from 'react';
import { 
  Play, 
  RotateCcw, 
  Code, 
  Download, 
  Layers, 
  Zap, 
  Sparkles
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
    <header className="fixed top-4 left-1/2 -translate-x-1/2 z-40 w-[95%] max-w-7xl">
      <div className="glass-panel rounded-lg px-6 py-3 border border-neutral-800 bg-neutral-900 flex items-center justify-between">
        {/* Brand & Jac Badge */}
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-md bg-neutral-800 border border-neutral-700 flex items-center justify-center">
            <Zap className="w-4 h-4 text-neutral-200" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="font-display text-xl font-bold tracking-tight text-white">Swirl</h1>
              <span className="jac-badge text-xs uppercase tracking-wider bg-neutral-800 text-neutral-300 border border-neutral-700">Jaclang v0.7.8</span>
            </div>
            <p className="text-xs text-neutral-400 font-mono">Scratch Block Canvas • macOS MCP Control Center</p>
          </div>
        </div>

        {/* Center Controls: Preset Selector & Preset Loader */}
        <div className="flex items-center gap-3">
          <div className="relative group">
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-md bg-neutral-800 border border-neutral-700 text-xs text-neutral-300 hover:bg-neutral-700 transition cursor-pointer">
              <Layers className="w-4 h-4 text-neutral-400" />
              <span>Load Preset Workflow</span>
            </div>
            <div className="absolute top-full left-0 mt-2 w-72 bg-neutral-900 border border-neutral-800 rounded-md p-2 hidden group-hover:block z-50 animate-fade-in shadow-xl">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-neutral-400 px-3 py-1.5 mb-1">
                Sample Jac Workflows
              </div>
              {WORKFLOW_PRESETS.map((preset) => (
                <button
                  key={preset.id}
                  onClick={() => onSelectPreset(preset)}
                  className="w-full text-left p-2.5 rounded hover:bg-neutral-800 transition flex flex-col gap-1 text-xs group/btn"
                >
                  <div className="font-medium text-neutral-200">
                    {preset.name}
                  </div>
                  <div className="text-[11px] text-neutral-400 line-clamp-2">
                    {preset.description}
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Stats Pill */}
          <div className="hidden md:flex items-center gap-3 px-3 py-1.5 rounded-md bg-neutral-950 border border-neutral-800 font-mono text-xs text-neutral-400">
            <span>Nodes: <strong className="text-neutral-200">{nodeCount}</strong></span>
            <span className="text-neutral-700">•</span>
            <span>Edges: <strong className="text-neutral-200">{edgeCount}</strong></span>
          </div>
        </div>

        {/* Right Controls: Run Execution, Speed, Jac Code View Toggle */}
        <div className="flex items-center gap-3">
          {/* Speed Toggle */}
          <div className="flex items-center bg-neutral-950 rounded-md p-0.5 border border-neutral-800 text-xs font-mono">
            {['1x', '2x', 'Step'].map((speed) => (
              <button
                key={speed}
                onClick={() => setExecutionSpeed(speed)}
                className={`px-2.5 py-1 rounded transition ${
                  executionSpeed === speed 
                    ? 'bg-neutral-700 text-white font-semibold' 
                    : 'text-neutral-400 hover:text-neutral-200'
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
            className={`flex items-center gap-2 px-4 py-2 rounded-md font-medium text-xs transition ${
              isExecuting
                ? 'bg-neutral-800 text-neutral-400 border border-neutral-700 cursor-wait'
                : nodeCount === 0
                ? 'bg-neutral-900 text-neutral-600 cursor-not-allowed border border-neutral-800'
                : 'bg-neutral-200 text-neutral-900 hover:bg-white font-semibold'
            }`}
          >
            {isExecuting ? (
              <>
                <Sparkles className="w-4 h-4 animate-spin text-neutral-400" />
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
            className={`flex items-center gap-2 px-3 py-2 rounded-md text-xs font-mono border transition ${
              showCodeView
                ? 'bg-neutral-700 text-white border-neutral-600'
                : 'bg-neutral-800 text-neutral-300 border-neutral-700 hover:bg-neutral-700'
            }`}
            title="Toggle Jac Code Emitter Panel"
          >
            <Code className="w-4 h-4 text-neutral-400" />
            <span className="hidden sm:inline">Jac Code</span>
          </button>

          {/* Export Jac Source Button */}
          <button
            onClick={onExportJac}
            className="p-2 rounded-md bg-neutral-800 text-neutral-300 border border-neutral-700 hover:bg-neutral-700 transition"
            title="Export Generated .jac File"
          >
            <Download className="w-4 h-4" />
          </button>

          {/* Clear Canvas */}
          <button
            onClick={onClearCanvas}
            className="p-2 rounded-md bg-neutral-800 text-neutral-400 border border-neutral-700 hover:bg-neutral-700 hover:text-neutral-200 transition"
            title="Clear Canvas"
          >
            <RotateCcw className="w-4 h-4" />
          </button>
        </div>
      </div>
    </header>
  );
}

