import React, { useState } from 'react';
import { Plus, Zap, Play, Sparkles, Command, Plug, GitBranch, Send, ArrowRight } from 'lucide-react';
import { BLOCK_LIBRARY } from '../data/blockDefinitions';

const CATEGORY_ICON_MAP = {
  Zap,
  Sparkles,
  Command,
  Plug,
  GitBranch,
  Send
};

export default function CodeBlockPalette({ onAddBlock }) {
  const [activeTab, setActiveTab] = useState('triggers'); // 'triggers' | 'actions'

  const handleDragStart = (e, blockType) => {
    e.dataTransfer.setData('application/swirl-block', JSON.stringify(blockType));
    e.dataTransfer.effectAllowed = 'copy';
  };

  const filteredBlocks = BLOCK_LIBRARY.filter((block) => {
    if (activeTab === 'triggers') {
      return block.category === 'trigger';
    }
    return block.category !== 'trigger' && block.category !== 'source';
  });

  return (
    <aside className="fixed right-6 top-20 bottom-6 z-40 w-80 rounded-3xl bg-neutral-950 border border-neutral-800 shadow-2xl p-5 flex flex-col justify-between">
      <div className="flex flex-col h-full overflow-hidden">
        {/* Header */}
        <div className="pb-3 border-b border-neutral-800 shrink-0">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-xs uppercase tracking-wider font-semibold text-neutral-200 font-sans">
                Building Blocks
              </h3>
              <p className="text-[11px] text-neutral-400 mt-0.5 font-sans">Drag onto canvas to build workflow</p>
            </div>
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
          </div>

          {/* User-friendly Tabs: Triggers vs Actions */}
          <div className="grid grid-cols-2 gap-1.5 p-1 mt-3.5 bg-neutral-900 border border-neutral-800 rounded-xl">
            <button
              onClick={() => setActiveTab('triggers')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-xs font-semibold transition font-sans ${
                activeTab === 'triggers'
                  ? 'bg-neutral-800 text-purple-300 border border-neutral-700 shadow-sm'
                  : 'text-neutral-400 hover:text-neutral-200'
              }`}
            >
              <Zap className="w-3.5 h-3.5 text-purple-400" />
              <span>Triggers</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-neutral-950 text-neutral-400 font-mono">
                {BLOCK_LIBRARY.filter((b) => b.category === 'trigger').length}
              </span>
            </button>

            <button
              onClick={() => setActiveTab('actions')}
              className={`flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-xs font-semibold transition font-sans ${
                activeTab === 'actions'
                  ? 'bg-neutral-800 text-amber-300 border border-neutral-700 shadow-sm'
                  : 'text-neutral-400 hover:text-neutral-200'
              }`}
            >
              <Play className="w-3.5 h-3.5 text-amber-400" />
              <span>Actions</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-neutral-950 text-neutral-400 font-mono">
                {BLOCK_LIBRARY.filter((b) => b.category !== 'trigger' && b.category !== 'source').length}
              </span>
            </button>
          </div>
        </div>

        {/* Tab Subtitle & Explanation */}
        <div className="py-2.5 px-1 shrink-0">
          <p className="text-[11px] text-neutral-400 font-sans">
            {activeTab === 'triggers'
              ? '⚡ What starts your automation:'
              : '🚀 What your agent will execute:'}
          </p>
        </div>

        {/* Block Items List */}
        <div className="space-y-2.5 overflow-y-auto flex-1 pr-1 pb-2">
          {filteredBlocks.map((block) => {
            const IconComp =
              block.category === 'ai' ? Sparkles :
              block.category === 'mac' ? Command :
              block.category === 'mcp' ? Plug :
              block.category === 'logic' ? GitBranch :
              block.category === 'output' ? Send : Zap;

            return (
              <div
                key={block.type}
                draggable
                onDragStart={(e) => handleDragStart(e, block)}
                className="group p-3 rounded-2xl bg-neutral-900 border border-neutral-800 hover:border-neutral-700 transition cursor-grab active:cursor-grabbing flex items-center justify-between shadow-sm"
              >
                <div className="flex items-center gap-3 overflow-hidden">
                  <div className={`p-2 rounded-xl border shrink-0 ${
                    block.category === 'trigger' ? 'bg-purple-950/60 border-purple-800/60 text-purple-300' :
                    block.category === 'ai' ? 'bg-amber-950/60 border-amber-800/60 text-amber-300' :
                    block.category === 'mac' ? 'bg-cyan-950/60 border-cyan-800/60 text-cyan-300' :
                    block.category === 'mcp' ? 'bg-emerald-950/60 border-emerald-800/60 text-emerald-300' :
                    block.category === 'output' ? 'bg-rose-950/60 border-rose-800/60 text-rose-300' :
                    'bg-indigo-950/60 border-indigo-800/60 text-indigo-300'
                  }`}>
                    <IconComp className="w-4 h-4" />
                  </div>
                  <div className="overflow-hidden">
                    <h4 className="text-xs font-semibold text-neutral-100 group-hover:text-white transition truncate font-sans">
                      {block.title}
                    </h4>
                    <p className="text-[10px] text-neutral-400 line-clamp-1 font-sans">
                      {block.description}
                    </p>
                  </div>
                </div>

                <button 
                  onClick={() => onAddBlock && onAddBlock(block)}
                  className="p-1.5 rounded-xl text-neutral-400 hover:text-white hover:bg-neutral-800 transition shrink-0 ml-2"
                  title="Add Block to Canvas"
                >
                  <Plus className="w-4 h-4" />
                </button>
              </div>
            );
          })}
        </div>

        {/* Footer Instructions */}
        <div className="pt-3 border-t border-neutral-800 shrink-0">
          <div className="p-2.5 rounded-2xl bg-neutral-900/60 border border-neutral-800 flex items-center gap-2 text-neutral-400">
            <ArrowRight className="w-3.5 h-3.5 text-neutral-400 shrink-0" />
            <p className="text-[11px] text-neutral-400 leading-snug font-sans">
              Drag any block onto the canvas, then connect the dots to link steps!
            </p>
          </div>
        </div>
      </div>
    </aside>
  );
}
