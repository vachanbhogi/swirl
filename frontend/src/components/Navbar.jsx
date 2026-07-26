import React from 'react';
import { Play, Code, RotateCcw, Zap } from 'lucide-react';

export default function Navbar({
  onRunWorkflow,
  isExecuting,
  onClearCanvas,
  showCodeView,
  setShowCodeView
}) {
  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 w-[90%] max-w-4xl">
      <nav className="rounded-full px-6 py-1.5 border border-neutral-800 bg-neutral-950/90 backdrop-blur-md flex items-center justify-between shadow-xl">
        {/* Brand */}
        <div className="flex items-center gap-2">
          <Zap className="w-3.5 h-3.5 text-white" />
          <span className="font-display text-sm font-bold text-white tracking-tight">Swirl</span>
        </div>

        {/* Essential Action Controls */}
        <div className="flex items-center gap-2">
          <button
            onClick={onRunWorkflow}
            disabled={isExecuting}
            className="flex items-center gap-1.5 px-4 py-1 rounded-full bg-white text-black text-xs font-semibold hover:bg-neutral-200 transition"
          >
            <Play className="w-3 h-3 fill-current" />
            <span>{isExecuting ? 'Running...' : 'Run'}</span>
          </button>

          <button
            onClick={() => setShowCodeView && setShowCodeView(!showCodeView)}
            className={`flex items-center gap-1.5 px-3.5 py-1 rounded-full text-xs font-medium border transition ${
              showCodeView
                ? 'bg-neutral-800 text-white border-neutral-700'
                : 'text-neutral-400 border-neutral-800 hover:text-white hover:border-neutral-700'
            }`}
          >
            <Code className="w-3 h-3" />
            <span>Code</span>
          </button>

          {onClearCanvas && (
            <button
              onClick={onClearCanvas}
              className="p-1.5 rounded-full text-neutral-400 border border-neutral-800 hover:text-white hover:border-neutral-700 transition"
              title="Clear"
            >
              <RotateCcw className="w-3 h-3" />
            </button>
          )}
        </div>
      </nav>
    </div>
  );
}
