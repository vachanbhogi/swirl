import React, { useState } from 'react';
import { Sparkles, Wand2, ArrowRight, CornerDownLeft } from 'lucide-react';

export default function PromptBar({ onGenerateFromPrompt, isCompilingPrompt }) {
  const [promptText, setPromptText] = useState('');

  const SUGGESTIONS = [
    {
      label: '📥 Email Summarizer -> Apple Notes',
      prompt: 'When I get a high priority email, summarize it with Jac LLM walker, create a task in Apple Notes, and show a Mac desktop notification.'
    },
    {
      label: '📁 Desktop File Organizer -> Slack',
      prompt: 'Organize files on my Desktop into folders by file extension using Finder, then post a summary message to Slack.'
    },
    {
      label: '🌐 MCP Scraper -> AI Digest',
      prompt: 'Fetch news content using stdio MCP scraper tool, run LLM entity extraction walker, and save summary note.'
    }
  ];

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!promptText.trim() || isCompilingPrompt) return;
    onGenerateFromPrompt(promptText);
  };

  const handleSelectSuggestion = (sugPrompt) => {
    setPromptText(sugPrompt);
    onGenerateFromPrompt(sugPrompt);
  };

  return (
    <div className="w-full bg-slate-950/70 border-b border-white/10 px-6 py-3 flex flex-col gap-2.5 z-20 backdrop-blur-md">
      <form onSubmit={handleSubmit} className="flex items-center gap-3">
        <div className="relative flex-1 prompt-input rounded-xl bg-slate-900/90 border border-white/15 overflow-hidden transition group">
          <div className="absolute left-3.5 top-1/2 -translate-y-1/2 text-purple-400">
            <Sparkles className="w-4 h-4 animate-pulse" />
          </div>

          <input
            type="text"
            value={promptText}
            onChange={(e) => setPromptText(e.target.value)}
            placeholder="✨ Prompt your workflow (e.g., Summarize unread emails with LLM walker, create Apple Note, and notify Slack)..."
            className="w-full bg-transparent py-2.5 pl-10 pr-24 text-sm text-slate-100 placeholder-slate-500 focus:outline-none font-sans"
            disabled={isCompilingPrompt}
          />

          <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
            <button
              type="submit"
              disabled={!promptText.trim() || isCompilingPrompt}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition shadow-md ${
                isCompilingPrompt
                  ? 'bg-purple-600/30 text-purple-300 border border-purple-500/40 cursor-wait'
                  : !promptText.trim()
                  ? 'bg-slate-800 text-slate-500 cursor-not-allowed'
                  : 'bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-500 hover:to-pink-500 text-white shadow-purple-500/20'
              }`}
            >
              {isCompilingPrompt ? (
                <>
                  <Wand2 className="w-3.5 h-3.5 animate-spin text-purple-300" />
                  <span>Compiling Jac AST...</span>
                </>
              ) : (
                <>
                  <Wand2 className="w-3.5 h-3.5" />
                  <span>Generate Graph</span>
                </>
              )}
            </button>
          </div>
        </div>
      </form>

      {/* Suggestion Chips */}
      <div className="flex items-center gap-2 overflow-x-auto pb-0.5 no-scrollbar text-xs">
        <span className="text-[11px] font-mono uppercase tracking-wider text-slate-400 flex items-center gap-1 shrink-0">
          <CornerDownLeft className="w-3 h-3 text-purple-400" /> Try Prompts:
        </span>
        {SUGGESTIONS.map((sug, i) => (
          <button
            key={i}
            onClick={() => handleSelectSuggestion(sug.prompt)}
            disabled={isCompilingPrompt}
            className="shrink-0 px-2.5 py-1 rounded-md bg-slate-900/60 border border-white/10 hover:border-purple-500/40 hover:bg-purple-500/10 text-slate-300 hover:text-purple-300 transition text-[11px] font-sans"
          >
            {sug.label}
          </button>
        ))}
      </div>
    </div>
  );
}
