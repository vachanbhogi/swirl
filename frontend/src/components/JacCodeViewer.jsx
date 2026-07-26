import React, { useState } from 'react';
import { Code, Copy, Check, Download, X, Sparkles, Terminal } from 'lucide-react';
import { generateJacCode } from '../data/blockDefinitions';

export default function JacCodeViewer({ nodes, edges, jacCode: generatedCode, onClose, onExportJac }) {
  const [copied, setCopied] = useState(false);
  const jacCode = generatedCode || generateJacCode(nodes, edges);

  const handleCopy = () => {
    navigator.clipboard.writeText(jacCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="w-96 glass-panel border-l border-white/10 flex flex-col h-[calc(100vh-8rem)] z-20 font-mono text-xs select-text">
      {/* Panel Header */}
      <div className="p-4 border-b border-white/10 flex items-center justify-between bg-slate-950/60">
        <div className="flex items-center gap-2">
          <div className="p-1.5 rounded-lg bg-pink-500/20 text-pink-400 border border-pink-500/30">
            <Code className="w-4 h-4" />
          </div>
          <div>
            <h3 className="font-bold text-slate-200 text-xs">Jaclang Source View</h3>
            <p className="text-[10px] text-slate-400">Real-Time Bi-Directional Sync</p>
          </div>
        </div>

        <div className="flex items-center gap-1.5">
          <button
            onClick={handleCopy}
            className="flex items-center gap-1 px-2.5 py-1 rounded-md bg-slate-900 border border-white/10 hover:border-pink-500/40 text-slate-300 hover:text-pink-300 transition text-[11px]"
            title="Copy Jac Code"
          >
            {copied ? (
              <>
                <Check className="w-3 h-3 text-emerald-400" />
                <span className="text-emerald-400">Copied</span>
              </>
            ) : (
              <>
                <Copy className="w-3 h-3 text-pink-400" />
                <span>Copy</span>
              </>
            )}
          </button>

          <button
            onClick={onExportJac}
            className="p-1.5 rounded-md bg-slate-900 border border-white/10 hover:border-cyan-500/40 text-slate-300 hover:text-cyan-300 transition"
            title="Download .jac File"
          >
            <Download className="w-3.5 h-3.5" />
          </button>

          {onClose && (
            <button
              onClick={onClose}
              className="p-1.5 rounded-md hover:bg-white/10 text-slate-400 hover:text-white transition"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Compiler Status Bar */}
      <div className="px-4 py-2 bg-slate-900/80 border-b border-white/5 flex items-center justify-between text-[11px] text-slate-400">
        <span className="flex items-center gap-1.5">
          <Sparkles className="w-3 h-3 text-amber-400 animate-pulse" />
          <span>AST Serializer: <strong className="text-pink-400 font-semibold">Active</strong></span>
        </span>
        <span className="text-[10px] text-slate-500">Target: workflow_agent.jac</span>
      </div>

      {/* Code Text Area */}
      <div className="flex-1 overflow-y-auto p-4 bg-slate-950/90 code-viewer-container">
        <pre className="text-[12px] text-slate-300 leading-relaxed font-mono whitespace-pre-wrap">
          {jacCode}
        </pre>
      </div>
    </div>
  );
}
