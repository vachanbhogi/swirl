import React, { useState } from 'react';
import { 
  Terminal, 
  Layers, 
  CheckCircle2, 
  RotateCcw, 
  Sparkles,
  X
} from 'lucide-react';

export default function ExecutionInspector({ isOpen, onClose, logs, activeNode, executionResults, onClearLogs }) {
  const [activeTab, setActiveTab] = useState('logs'); // 'logs' | 'node' | 'payload'

  if (!isOpen) return null;

  return (
    <div className="absolute bottom-4 left-4 right-4 z-40 max-h-64 bg-slate-950/95 border border-slate-800 rounded-2xl shadow-2xl backdrop-blur-xl text-slate-100 flex flex-col overflow-hidden animate-slide-up">
      {/* Drawer Header */}
      <div className="h-10 px-4 bg-slate-900/90 border-b border-slate-800 flex items-center justify-between font-mono text-xs select-none">
        <div className="flex items-center gap-3">
          <button
            onClick={() => setActiveTab('logs')}
            className={`flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition ${
              activeTab === 'logs'
                ? 'bg-purple-950/70 text-purple-300 font-bold border border-purple-800/50'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Terminal className="w-3.5 h-3.5" />
            <span>Walker Logs ({logs.length})</span>
          </button>

          <button
            onClick={() => setActiveTab('node')}
            className={`flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition ${
              activeTab === 'node'
                ? 'bg-cyan-950/70 text-cyan-300 font-bold border border-cyan-800/50'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Layers className="w-3.5 h-3.5" />
            <span>Node Inspector</span>
          </button>

          <button
            onClick={() => setActiveTab('payload')}
            className={`flex items-center gap-1.5 py-1 px-2.5 rounded-lg transition ${
              activeTab === 'payload'
                ? 'bg-emerald-950/70 text-emerald-300 font-bold border border-emerald-800/50'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5" />
            <span>Agent Outputs ({Object.keys(executionResults || {}).length})</span>
          </button>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={onClearLogs}
            className="p-1 rounded-md text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
            title="Clear Logs"
          >
            <RotateCcw className="w-3.5 h-3.5" />
          </button>

          <button
            onClick={onClose}
            className="p-1 rounded-md text-slate-400 hover:text-rose-400 hover:bg-slate-800 transition"
            title="Close Inspector"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Drawer Body */}
      <div className="flex-1 overflow-y-auto p-3.5 bg-slate-950/90 font-mono text-xs">
        {/* Logs Tab */}
        {activeTab === 'logs' && (
          <div className="space-y-1.5">
            {logs.length === 0 ? (
              <div className="text-slate-500 italic py-3 text-center">
                No execution logs yet. Click "Run" to begin Jac graph traversal.
              </div>
            ) : (
              logs.map((log, idx) => (
                <div key={idx} className="flex items-start gap-2 text-slate-300 hover:bg-white/5 p-1 rounded transition">
                  <span className="text-slate-500 shrink-0 text-[11px]">[{log.time}]</span>
                  <span className={`shrink-0 font-bold ${
                    log.type === 'error' ? 'text-rose-400' : log.type === 'success' ? 'text-emerald-400' : 'text-purple-400'
                  }`}>
                    {log.prefix}
                  </span>
                  <span className="text-slate-200 flex-1">{log.message}</span>
                </div>
              ))
            )}
          </div>
        )}

        {/* Node Inspector Tab */}
        {activeTab === 'node' && (
          <div className="space-y-3">
            {activeNode ? (
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-slate-900/80 p-3 rounded-lg border border-slate-800">
                  <h4 className="font-bold text-purple-300 mb-1">{activeNode.title}</h4>
                  <p className="text-[11px] text-slate-400 mb-2">ID: {activeNode.id} | Category: {activeNode.category}</p>
                  <div className="space-y-1 text-[11px]">
                    <div><strong className="text-slate-400">Jac Class:</strong> {activeNode.jacNode || 'WorkflowBlock'}</div>
                    <div><strong className="text-slate-400">Status:</strong> <span className="text-emerald-400">{activeNode.status}</span></div>
                  </div>
                </div>

                <div className="bg-slate-900/80 p-3 rounded-lg border border-slate-800">
                  <h4 className="font-bold text-amber-300 mb-1">Configuration Parameters</h4>
                  <pre className="text-[11px] text-amber-200 bg-slate-950 p-2 rounded overflow-x-auto">
                    {JSON.stringify(activeNode.config, null, 2)}
                  </pre>
                </div>
              </div>
            ) : (
              <div className="text-slate-500 italic py-3 text-center">
                Select a node on the canvas to inspect its configuration & execution context.
              </div>
            )}
          </div>
        )}

        {/* Agent Payload Tab */}
        {activeTab === 'payload' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {Object.keys(executionResults || {}).length === 0 ? (
              <div className="text-slate-500 italic py-3 text-center col-span-2">
                No execution results generated yet. Run the workflow to inspect output cards.
              </div>
            ) : (
              Object.entries(executionResults).map(([nodeId, result]) => (
                <div key={nodeId} className="bg-slate-900/90 border border-emerald-500/30 p-3.5 rounded-xl shadow-lg">
                  <div className="flex items-center justify-between mb-2">
                    <span className="flex items-center gap-1.5 font-bold text-emerald-300 text-xs">
                      <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                      Node Output ({nodeId})
                    </span>
                    <span className="text-[10px] bg-emerald-500/20 text-emerald-300 px-2 py-0.5 rounded border border-emerald-500/40">
                      SUCCESS
                    </span>
                  </div>
                  <div className="bg-slate-950 p-2.5 rounded-lg text-slate-200 text-xs font-mono space-y-1">
                    {typeof result === 'object' ? (
                      Object.entries(result).map(([k, v]) => (
                        <div key={k}>
                          <strong className="text-cyan-300">{k}:</strong> {String(v)}
                        </div>
                      ))
                    ) : (
                      <div>{String(result)}</div>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}
