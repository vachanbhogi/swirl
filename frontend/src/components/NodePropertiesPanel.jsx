import React, { useState, useEffect } from 'react';
import { 
  X, 
  Settings, 
  Trash2, 
  CheckCircle2, 
  HelpCircle,
  Play,
  Layers,
  Copy
} from 'lucide-react';
import { BLOCK_CATEGORIES } from '../data/blockDefinitions';
import { changeSourceEvent, SOURCE_EVENTS } from '../data/workflowNormalization';

const CATEGORY_BG_MAP = {
  source: 'bg-orange-500/10 border-orange-500/30 text-orange-400',
  trigger: 'bg-purple-500/10 border-purple-500/30 text-purple-400',
  ai: 'bg-amber-500/10 border-amber-500/30 text-amber-400',
  mac: 'bg-cyan-500/10 border-cyan-500/30 text-cyan-400',
  mcp: 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400',
  logic: 'bg-indigo-500/10 border-indigo-500/30 text-indigo-400',
  output: 'bg-rose-500/10 border-rose-500/30 text-rose-400'
};

const FRIENDLY_KEY_LABELS = {
  mailbox: '📥 Target Mailbox',
  filterSubject: '🔍 Filter Subject (optional)',
  checkIntervalSec: '⏱️ Check Every (seconds)',
  waitTimeoutSec: '⌛ Stop Waiting After (seconds, 0 = never)',
  runMode: '🔁 Run Mode',
  cron: '📅 Schedule Pattern (Cron)',
  timezone: '🌐 Timezone',
  wakeWord: '🎙️ Voice Wake Word',
  language: '🗣️ Recognition Language',
  listenTimeoutSec: '⌛ Whisper Poll Timeout (seconds)',
  prompt: '✨ AI Assistant Instructions',
  maxTokens: '📏 Response Detail Level',
  temperature: '🎨 AI Creativity (0 = Precise, 1 = Creative)',
  app: '💻 macOS Application',
  action: '⚡ Action to Perform',
  folder: '📁 Target Folder',
  defaultTitle: '📝 Note Title',
  targetDirectory: '📂 Destination Directory',
  command: '💻 Terminal Command',
  server: '🔌 MCP Server Name',
  tool_name: '🛠️ Tool Function Name',
  channel: '💬 Slack Channel',
  webhookUrl: '🔗 Webhook URL',
  watchPath: '📂 Watched Directory',
  filePattern: '📄 File Pattern',
  host: '🌐 Listener Host',
  port: '🔌 Listener Port',
  path: '↪ Webhook Path',
  method: 'HTTP Method',
  authRequired: '🔒 Require Bearer Token',
  authToken: '🔑 Bearer Token',
  watchText: '📋 Watch Text',
  minChars: 'Minimum Characters'
};

export default function NodePropertiesPanel({
  selectedNode,
  onSaveNodeConfig,
  onDeleteNode,
  onDuplicateNode,
  onClose,
  totalNodes,
  totalEdges,
  onRunWorkflow
}) {
  const [config, setConfig] = useState({});
  const [title, setTitle] = useState('');

  useEffect(() => {
    if (selectedNode) {
      setConfig(selectedNode.config || {});
      setTitle(selectedNode.title || '');
    }
  }, [selectedNode]);

  if (!selectedNode) {
    return (
      <aside className="w-80 h-full bg-zinc-950 border-l border-zinc-800 p-5 flex flex-col justify-between overflow-y-auto select-none shrink-0">
        <div className="space-y-6">
          <div className="pb-4 border-b border-zinc-800">
            <div className="flex items-center gap-2">
              <div className="p-2 rounded-xl bg-zinc-800 text-zinc-300">
                <Layers className="w-4 h-4" />
              </div>
              <div>
                <h3 className="font-bold text-white text-sm">Block Inspector</h3>
                <p className="text-xs text-zinc-400 font-sans">Swirl Agent Workspace</p>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="p-3.5 rounded-2xl bg-zinc-900 border border-zinc-800">
              <span className="text-2xl font-bold font-display text-white">{totalNodes}</span>
              <p className="text-[11px] font-medium text-zinc-400 mt-0.5">Total Blocks</p>
            </div>
            <div className="p-3.5 rounded-2xl bg-zinc-900 border border-zinc-800">
              <span className="text-2xl font-bold font-display text-white">{totalEdges}</span>
              <p className="text-[11px] font-medium text-zinc-400 mt-0.5">Connected Wires</p>
            </div>
          </div>
        </div>

        <div className="pt-4 border-t border-zinc-800">
          <button
            onClick={onRunWorkflow}
            className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl bg-white text-zinc-900 font-semibold text-xs transition shadow-sm hover:bg-zinc-200"
          >
            <Play className="w-3.5 h-3.5 fill-current" />
            <span>Run Workflow</span>
          </button>
        </div>
      </aside>
    );
  }

  const isSource = selectedNode.category === 'source';
  const catObj = BLOCK_CATEGORIES.find((c) => c.id === selectedNode.category) || BLOCK_CATEGORIES[0];
  const catClass = CATEGORY_BG_MAP[selectedNode.category] || CATEGORY_BG_MAP.ai;

  const handleFieldChange = (key, value) => {
    const updated = { ...config, [key]: value };
    setConfig(updated);
    onSaveNodeConfig(selectedNode.id, title, updated);
  };

  const handleTitleChange = (val) => {
    setTitle(val);
    onSaveNodeConfig(selectedNode.id, val, config);
  };

  const handleSourceEventChange = (eventType) => {
    const updated = changeSourceEvent(eventType, config);
    setConfig(updated);
    onSaveNodeConfig(selectedNode.id, title, updated);
  };

  return (
    <aside className="w-80 h-full bg-zinc-950 border-l border-zinc-800 p-5 flex flex-col justify-between overflow-y-auto select-none shrink-0 animate-slide-up">
      <div className="space-y-5">
        <div className="pb-3 border-b border-zinc-800 flex items-center justify-between">
          <div className="flex items-center gap-2.5 overflow-hidden">
            <div className={`p-2 rounded-xl border shrink-0 ${catClass}`}>
              <Settings className="w-4 h-4" />
            </div>
            <div className="overflow-hidden">
              <h3 className="font-bold text-white text-xs truncate font-sans">
                Block Inspector
              </h3>
              <p className="text-[10px] text-zinc-400 font-sans truncate">
                {catObj.name}
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div>
          <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
            Block Title
          </label>
          <input
            type="text"
            value={title}
            onChange={(e) => handleTitleChange(e.target.value)}
            className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-700 transition font-sans"
          />
        </div>

        {isSource && (
          <div>
            <label className="block text-[11px] font-bold text-zinc-300 uppercase tracking-wider mb-1 font-sans">
              Trigger Event Type
            </label>
            <select
              value={config.eventType || 'trigger_email'}
              onChange={(e) => handleSourceEventChange(e.target.value)}
              className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-700 font-sans"
            >
              {Object.entries(SOURCE_EVENTS).map(([eventType, event]) => (
                <option key={eventType} value={eventType}>
                  {event.title}
                </option>
              ))}
            </select>
          </div>
        )}

        <div className="space-y-4 pt-2">
          <div className="flex items-center justify-between text-[11px] font-bold text-zinc-400 uppercase tracking-wider">
            <span>Configurable Settings</span>
            <HelpCircle className="w-3.5 h-3.5 text-zinc-500" />
          </div>

          {Object.entries(config)
            .filter(([key]) => !isSource || key !== 'eventType')
            .map(([key, val]) => {
              const label = FRIENDLY_KEY_LABELS[key] || key;

              return (
                <div key={key} className="space-y-1">
                  <label className="block text-[11px] font-medium text-zinc-300 font-sans">
                    {label}
                  </label>

                  {isSource && key === 'runMode' ? (
                    <select
                      value={val}
                      onChange={(e) => handleFieldChange(key, e.target.value)}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-semibold text-white focus:outline-none focus:border-zinc-600"
                    >
                      <option value="once">Once — stop after one event</option>
                      <option value="continuous">Continuous — re-arm until stopped</option>
                    </select>
                  ) : typeof val === 'number' && isSource ? (
                    <input
                      type="number"
                      min={key === 'waitTimeoutSec' ? 0 : 1}
                      max={key === 'port' ? 65535 : undefined}
                      value={val}
                      onChange={(e) => handleFieldChange(key, Number(e.target.value))}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-mono text-zinc-200 focus:outline-none focus:border-zinc-600"
                    />
                  ) : typeof val === 'number' ? (
                    <div className="flex items-center gap-2">
                      <input
                        type="range"
                        min={key === 'temperature' ? 0 : 1}
                        max={key === 'temperature' ? 1 : 3000}
                        step={key === 'temperature' ? 0.1 : 10}
                        value={val}
                        onChange={(e) => handleFieldChange(key, parseFloat(e.target.value))}
                        className="flex-1 accent-zinc-200"
                      />
                      <span className="text-xs font-mono font-bold text-white w-12 text-right">
                        {val}
                      </span>
                    </div>
                  ) : typeof val === 'boolean' ? (
                    <button
                      type="button"
                      onClick={() => handleFieldChange(key, !val)}
                      className={`w-full py-1.5 px-3 rounded-xl text-xs font-semibold border transition text-left flex items-center justify-between ${
                        val
                          ? 'bg-zinc-800 border-zinc-700 text-white'
                          : 'bg-zinc-900 border-zinc-800 text-zinc-400'
                      }`}
                    >
                      <span>{val ? 'Enabled' : 'Disabled'}</span>
                      <CheckCircle2 className={`w-4 h-4 ${val ? 'text-white' : 'text-zinc-500'}`} />
                    </button>
                  ) : (
                    <textarea
                      rows={typeof val === 'string' && val.length > 35 ? 3 : 1}
                      value={val}
                      onChange={(e) => handleFieldChange(key, e.target.value)}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 text-xs font-sans text-zinc-200 focus:outline-none focus:border-zinc-700 transition resize-none"
                    />
                  )}
                </div>
              );
            })}
        </div>
      </div>

      <div className="pt-4 border-t border-zinc-800 flex items-center justify-between gap-2">
        {onDuplicateNode && !isSource && (
          <button
            onClick={() => onDuplicateNode(selectedNode)}
            className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-semibold transition"
          >
            <Copy className="w-3.5 h-3.5" />
            <span>Duplicate</span>
          </button>
        )}

        {!isSource && (
          <button
            onClick={() => onDeleteNode(selectedNode.id)}
            className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-rose-950/40 hover:bg-rose-900/60 text-rose-300 text-xs font-semibold transition border border-rose-800/50"
            title="Remove block"
          >
            <Trash2 className="w-3.5 h-3.5" />
            <span>Delete</span>
          </button>
        )}
      </div>
    </aside>
  );
}
