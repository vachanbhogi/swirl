import React, { useState, useRef, useEffect } from 'react';
import { Save, X } from 'lucide-react';

const NAME_REGEX = /^[a-zA-Z0-9 _-]{1,80}$/;

export default function SaveWorkflowModal({ onSave, onClose, existingNames = [] }) {
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const inputRef = useRef(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  const validate = (value) => {
    const trimmed = value.trim();
    if (!trimmed) {
      setError('Name is required');
      return false;
    }
    if (!NAME_REGEX.test(trimmed)) {
      setError('1-80 chars: letters, numbers, spaces, hyphens, underscores only');
      return false;
    }
    if (existingNames.includes(trimmed)) {
      setError('A workflow with this name already exists');
      return false;
    }
    setError('');
    return true;
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!validate(name)) return;
    onSave(name.trim());
  };

  const handleChange = (e) => {
    setName(e.target.value);
    if (error) validate(e.target.value);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div
        className="w-full max-w-sm mx-4 rounded-2xl bg-zinc-950 border border-zinc-800 shadow-2xl p-6 space-y-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold text-white">Save Workflow</h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg text-zinc-500 hover:text-white hover:bg-zinc-800 transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
              Workflow Name
            </label>
            <input
              ref={inputRef}
              type="text"
              value={name}
              onChange={handleChange}
              placeholder="e.g. Email Summarizer"
              className={`w-full px-3 py-2 rounded-xl bg-zinc-900 border text-sm text-white placeholder-zinc-600 focus:outline-none focus:ring-1 transition ${
                error
                  ? 'border-red-600 focus:ring-red-600'
                  : 'border-zinc-800 focus:ring-blue-600 focus:border-blue-600'
              }`}
            />
            {error && (
              <p className="text-[11px] text-red-400">{error}</p>
            )}
          </div>

          <div className="flex items-center justify-end gap-2 pt-1">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-semibold text-zinc-400 hover:text-white hover:bg-zinc-800 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold bg-white text-zinc-950 hover:bg-zinc-200 shadow-sm active:scale-95 transition"
            >
              <Save className="w-3.5 h-3.5" />
              <span>Save</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
