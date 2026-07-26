import React, { useState } from 'react';
import { X, Settings, Save, Sparkles } from 'lucide-react';

export default function NodeConfigModal({ node, onSave, onClose }) {
  const [config, setConfig] = useState(node.config || {});
  const [title, setTitle] = useState(node.title || '');

  const handleFieldChange = (key, value) => {
    setConfig((prev) => ({ ...prev, [key]: value }));
  };

  const handleSave = (e) => {
    e.preventDefault();
    onSave(node.id, title, config);
  };

  return (
  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4 animate-fade-in">
      <div className="w-full max-w-md bg-neutral-950 rounded-2xl p-6 border border-neutral-800 shadow-2xl relative">
        {/* Modal Header */}
        <div className="flex items-center justify-between pb-4 border-b border-neutral-800 mb-4">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-xl bg-neutral-900 text-neutral-200 border border-neutral-800">
              <Settings className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-neutral-100 text-sm">Configure Block Parameters</h3>
              <p className="text-xs text-neutral-400 font-mono">Jac Class: {node.jacNode || 'WorkflowBlock'}</p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-neutral-800 text-neutral-400 hover:text-white transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Modal Form */}
        <form onSubmit={handleSave} className="space-y-4">
          {/* Title Field */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-neutral-300 mb-1.5 font-mono">
              Block Label / Title
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full bg-neutral-900 border border-neutral-800 rounded-xl px-3.5 py-2 text-xs text-neutral-100 focus:outline-none focus:border-neutral-600 font-sans"
            />
          </div>

          {/* Dynamic Configuration Fields */}
          <div className="space-y-3 pt-2">
            <h4 className="text-xs font-semibold text-neutral-300 uppercase tracking-wider font-mono">
              Configuration Keys
            </h4>

            {Object.entries(config).map(([key, val]) => (
              <div key={key}>
                <label className="block text-[11px] font-mono text-neutral-400 mb-1">
                  {key}
                </label>
                {typeof val === 'number' ? (
                  <input
                    type="number"
                    value={val}
                    onChange={(e) => handleFieldChange(key, parseFloat(e.target.value) || 0)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-1.5 text-xs text-neutral-200 font-mono focus:outline-none focus:border-neutral-600"
                  />
                ) : typeof val === 'boolean' ? (
                  <select
                    value={val ? 'true' : 'false'}
                    onChange={(e) => handleFieldChange(key, e.target.value === 'true')}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-1.5 text-xs text-neutral-200 font-mono focus:outline-none focus:border-neutral-600"
                  >
                    <option value="true">True</option>
                    <option value="false">False</option>
                  </select>
                ) : (
                  <textarea
                    rows={typeof val === 'string' && val.length > 40 ? 3 : 1}
                    value={val}
                    onChange={(e) => handleFieldChange(key, e.target.value)}
                    className="w-full bg-neutral-900 border border-neutral-800 rounded-lg px-3 py-1.5 text-xs text-neutral-200 font-mono focus:outline-none focus:border-neutral-600 resize-none"
                  />
                )}
              </div>
            ))}
          </div>

          {/* Action Buttons */}
          <div className="flex items-center justify-end gap-2 pt-4 border-t border-neutral-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl bg-neutral-900 text-neutral-300 border border-neutral-800 hover:bg-neutral-800 text-xs font-medium transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-white text-black hover:bg-neutral-200 text-xs font-semibold transition"
            >
              <Save className="w-3.5 h-3.5" />
              <span>Save Parameters</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
