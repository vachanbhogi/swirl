import React, { useState } from 'react';
import { FolderOpen, Plus, Trash2, ExternalLink, Layers, RefreshCw, Clock } from 'lucide-react';

function timeAgo(timestamp) {
  if (!timestamp) return '';
  const seconds = Math.floor(Date.now() / 1000 - timestamp);
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export default function WorkflowsScreen({
  savedWorkflows,
  currentWorkflowName,
  onNew,
  onLoad,
  onDelete,
  onRefresh
}) {
  const [confirmDelete, setConfirmDelete] = useState(null);

  const handleConfirmDelete = (name) => {
    if (confirmDelete === name) {
      onDelete(name);
      setConfirmDelete(null);
    } else {
      setConfirmDelete(name);
    }
  };

  return (
    <div className="flex-1 w-full h-full bg-[#050508] text-white flex flex-col overflow-hidden font-sans select-none">
      <div className="flex-1 flex items-start justify-center p-8 overflow-y-auto">
        <div className="w-full max-w-4xl flex flex-col space-y-8">

          {/* Header */}
          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-blue-500/20 to-cyan-500/20 border border-blue-500/20 flex items-center justify-center">
                  <FolderOpen className="w-5 h-5 text-blue-400" />
                </div>
                <h1 className="text-2xl font-extrabold tracking-tight text-white">
                  My Workflows
                </h1>
              </div>
              <p className="text-sm text-zinc-500 ml-[52px]">
                Manage, open, and create your automation workflows.
              </p>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={onRefresh}
                className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold bg-zinc-900 text-zinc-400 border border-zinc-800 hover:text-white hover:border-zinc-700 transition"
                title="Refresh list"
              >
                <RefreshCw className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={onNew}
                className="flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold bg-white text-zinc-950 hover:bg-zinc-200 shadow-sm active:scale-95 transition"
              >
                <Plus className="w-3.5 h-3.5" />
                <span>New Workflow</span>
              </button>
            </div>
          </div>

          {/* Workflow Grid */}
          {savedWorkflows.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-24 space-y-4 text-center">
              <div className="w-16 h-16 rounded-3xl bg-zinc-900 border border-zinc-800 flex items-center justify-center">
                <Layers className="w-7 h-7 text-zinc-600" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-bold text-zinc-400">No workflows yet</h3>
                <p className="text-xs text-zinc-600 max-w-xs">
                  Create your first workflow or use the AI Builder to generate one from a prompt.
                </p>
              </div>
              <button
                onClick={onNew}
                className="flex items-center gap-2 px-5 py-2.5 rounded-2xl text-xs font-bold bg-white text-zinc-950 hover:bg-zinc-200 shadow-lg active:scale-95 transition"
              >
                <Plus className="w-4 h-4" />
                <span>Create your first workflow</span>
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {savedWorkflows.map((record) => {
                const isCurrent = record.name === currentWorkflowName;
                const isConfirming = confirmDelete === record.name;
                const nodeCount = record.workflow?.nodes?.length || 0;

                return (
                  <div
                    key={record.name}
                    className={`group p-4 rounded-2xl border transition-all flex flex-col justify-between space-y-3 ${
                      isCurrent
                        ? 'bg-blue-950/30 border-blue-700/50 shadow-md shadow-blue-950/20'
                        : 'bg-zinc-950 border-zinc-800 hover:border-zinc-700 hover:bg-zinc-900/60'
                    }`}
                  >
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <h4 className="text-sm font-bold text-white truncate pr-2" title={record.name}>
                          {record.name}
                        </h4>
                        {isCurrent && (
                          <span className="text-[10px] font-bold uppercase tracking-wider text-blue-400 bg-blue-950/60 px-2 py-0.5 rounded-lg shrink-0">
                            Open
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-3 text-[11px] text-zinc-500">
                        <span className="flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          {timeAgo(record.updated_at)}
                        </span>
                        <span className="flex items-center gap-1">
                          <Layers className="w-3 h-3" />
                          {nodeCount} node{nodeCount !== 1 ? 's' : ''}
                        </span>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 pt-1 border-t border-zinc-800/50">
                      <button
                        onClick={() => onLoad(record.name)}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[11px] font-bold bg-zinc-800 text-white hover:bg-zinc-700 transition active:scale-95"
                      >
                        <ExternalLink className="w-3 h-3" />
                        <span>Open</span>
                      </button>

                      <button
                        onClick={() => handleConfirmDelete(record.name)}
                        onBlur={() => setConfirmDelete(null)}
                        className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[11px] font-bold transition active:scale-95 ${
                          isConfirming
                            ? 'bg-red-900/80 text-red-200 border border-red-700'
                            : 'bg-zinc-800/50 text-zinc-500 hover:text-red-400 hover:bg-red-950/40'
                        }`}
                      >
                        <Trash2 className="w-3 h-3" />
                        <span>{isConfirming ? 'Confirm' : 'Delete'}</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
