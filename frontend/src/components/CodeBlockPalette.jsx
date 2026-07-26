import React from 'react';
import { Plus, Box, Zap, Cpu, Terminal, ArrowRight } from 'lucide-react';

const BLOCK_TYPES = [
  { id: 'trigger', label: 'Trigger Event', icon: Zap, category: 'Trigger' },
  { id: 'llm', label: 'LLM Reasoning', icon: Cpu, category: 'AI Transform' },
  { id: 'mac', label: 'Mac App Action', icon: Box, category: 'macOS Native' },
  { id: 'mcp', label: 'MCP Tool Call', icon: Terminal, category: 'MCP Adapter' }
];

export default function CodeBlockPalette() {
  return (
    <aside className="fixed right-6 top-20 bottom-6 z-40 w-72 rounded-3xl bg-neutral-950 border border-neutral-800 shadow-2xl p-5 flex flex-col justify-between">
      <div>
        {/* Header */}
        <div className="flex items-center justify-between pb-4 mb-4 border-b border-neutral-800">
          <div>
            <h3 className="text-xs font-mono uppercase tracking-wider font-semibold text-neutral-200">
              Agent Tool Library
            </h3>
            <p className="text-[11px] text-neutral-400 mt-0.5">Drag blocks onto canvas to build</p>
          </div>
          <span className="w-2 h-2 rounded-full bg-neutral-500"></span>
        </div>

        {/* Block Items */}
        <div className="space-y-2.5">
          {BLOCK_TYPES.map((block) => {
            const Icon = block.icon;
            return (
              <div
                key={block.id}
                className="group p-3 rounded-2xl bg-neutral-950 border border-neutral-800 hover:border-neutral-700 transition cursor-grab active:cursor-grabbing flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-xl bg-neutral-900 border border-neutral-800 text-neutral-300">
                    <Icon className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="text-xs font-medium text-neutral-200 group-hover:text-white transition">
                      {block.label}
                    </h4>
                    <span className="text-[10px] text-neutral-500 font-mono">
                      {block.category}
                    </span>
                  </div>
                </div>

                <button 
                  className="p-1.5 rounded-lg text-neutral-500 hover:text-white hover:bg-neutral-800 transition"
                  title="Add Block"
                >
                  <Plus className="w-3.5 h-3.5" />
                </button>
              </div>
            );
          })}
        </div>
      </div>

      {/* Footer Instructions */}
      <div className="pt-4 border-t border-neutral-800">
        <div className="p-3 rounded-2xl bg-neutral-900/60 border border-neutral-800 flex items-center gap-2 text-neutral-400">
          <ArrowRight className="w-3.5 h-3.5 text-neutral-400 shrink-0" />
          <p className="text-[11px] text-neutral-400 leading-snug">
            Connect nodes on the canvas to assemble Jac Walker agent logic.
          </p>
        </div>
      </div>
    </aside>
  );
}
