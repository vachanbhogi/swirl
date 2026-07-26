import React, { useState } from 'react';
import { 
  Zap, 
  Sparkles, 
  Command, 
  Plug, 
  GitBranch, 
  Send, 
  Plus, 
  Search, 
  GripVertical,
  HelpCircle
} from 'lucide-react';
import { BLOCK_CATEGORIES, BLOCK_LIBRARY } from '../data/blockDefinitions';

const ICON_MAP = {
  Zap,
  Sparkles,
  Command,
  Plug,
  GitBranch,
  Send
};

export default function BlockPalette({ onAddNode }) {
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');

  const filteredBlocks = BLOCK_LIBRARY.filter((block) => {
    const matchesCat = selectedCategory === 'all' || block.category === selectedCategory;
    const matchesSearch = block.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          block.description.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCat && matchesSearch;
  });

  const handleDragStart = (e, block) => {
    e.dataTransfer.setData('application/swirl-block', JSON.stringify(block));
    e.dataTransfer.effectAllowed = 'copy';
  };

  return (
    <aside className="w-72 glass-panel border-r border-white/10 flex flex-col h-[calc(100vh-8rem)] z-10 select-none">
      {/* Sidebar Header & Search */}
      <div className="p-4 border-b border-white/10 space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-300 flex items-center gap-1.5 font-mono">
            <Sparkles className="w-3.5 h-3.5 text-purple-400" />
            Scratch Block Palette
          </h2>
          <span className="text-[10px] text-slate-400 bg-slate-900/80 px-2 py-0.5 rounded border border-white/10 font-mono">
            Drag to Canvas
          </span>
        </div>

        <div className="relative">
          <Search className="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
          <input
            type="text"
            placeholder="Search Jac blocks..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-slate-900/80 border border-white/10 rounded-lg pl-8 pr-3 py-1.5 text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-purple-500/50"
          />
        </div>
      </div>

      {/* Category Pills */}
      <div className="px-3 py-2 border-b border-white/10 flex items-center gap-1.5 overflow-x-auto no-scrollbar">
        <button
          onClick={() => setSelectedCategory('all')}
          className={`px-2.5 py-1 rounded-md text-[11px] font-mono transition shrink-0 ${
            selectedCategory === 'all'
              ? 'bg-purple-600/30 text-purple-300 border border-purple-500/50'
              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-900'
          }`}
        >
          All
        </button>
        {BLOCK_CATEGORIES.map((cat) => {
          const IconComp = ICON_MAP[cat.icon] || Zap;
          const isActive = selectedCategory === cat.id;
          return (
            <button
              key={cat.id}
              onClick={() => setSelectedCategory(cat.id)}
              className={`flex items-center gap-1 px-2.5 py-1 rounded-md text-[11px] font-sans transition shrink-0 border ${
                isActive
                  ? 'bg-white/10 text-white font-medium border-white/20'
                  : 'text-slate-400 hover:text-slate-200 border-transparent hover:border-white/10'
              }`}
              style={{ color: isActive ? cat.color : undefined }}
            >
              <IconComp className="w-3 h-3" />
              <span>{cat.name.split(' ')[0]}</span>
            </button>
          );
        })}
      </div>

      {/* Block List */}
      <div className="flex-1 overflow-y-auto p-3 space-y-2.5">
        {filteredBlocks.length === 0 ? (
          <div className="text-center py-8 text-xs text-slate-500 font-mono">
            No matching blocks found
          </div>
        ) : (
          filteredBlocks.map((block) => {
            const catObj = BLOCK_CATEGORIES.find(c => c.id === block.category) || BLOCK_CATEGORIES[0];
            const IconComp = ICON_MAP[catObj.icon] || Zap;

            return (
              <div
                key={block.type}
                draggable
                onDragStart={(e) => handleDragStart(e, block)}
                className={`scratch-block block-cat-${block.category} p-3 rounded-xl border relative group cursor-grab active:cursor-grabbing hover:border-white/40 transition`}
              >
                {/* Drag Handle & Top Title */}
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <div
                      className="w-6 h-6 rounded-lg flex items-center justify-center text-white shrink-0 shadow-sm"
                      style={{ backgroundColor: catObj.color }}
                    >
                      <IconComp className="w-3.5 h-3.5" />
                    </div>
                    <div>
                      <h3 className="text-xs font-bold text-slate-100 group-hover:text-white">
                        {block.title}
                      </h3>
                      <p className="text-[10px] text-slate-400 font-mono">
                        {block.subtitle}
                      </p>
                    </div>
                  </div>

                  <button
                    onClick={() => onAddNode(block)}
                    className="p-1 rounded-md bg-white/10 hover:bg-white/20 text-slate-300 hover:text-white transition opacity-0 group-hover:opacity-100"
                    title="Add Block to Canvas"
                  >
                    <Plus className="w-3.5 h-3.5" />
                  </button>
                </div>

                {/* Description */}
                <p className="text-[11px] text-slate-300 leading-snug line-clamp-2 mt-1">
                  {block.description}
                </p>

                {/* Notch Ports Visual Indicator */}
                <div className="mt-2.5 pt-2 border-t border-white/10 flex items-center justify-between text-[10px] font-mono text-slate-400">
                  <span className="flex items-center gap-1">
                    <span className="w-2 h-2 rounded-full bg-slate-500 inline-block"></span>
                    In: {block.inputs.length || 0}
                  </span>
                  <span className="flex items-center gap-1">
                    Out: {block.outputs.length || 0}
                    <span className="w-2 h-2 rounded-full bg-slate-400 inline-block"></span>
                  </span>
                </div>
              </div>
            );
          })
        )}
      </div>
    </aside>
  );
}
