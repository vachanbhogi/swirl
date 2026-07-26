import React, { useState } from 'react';
import { Sparkles, ArrowRight, Wand2, Loader2, Bot, Cpu, ArrowLeft } from 'lucide-react';

const PRESET_PROMPTS = [
  {
    title: 'Email & Notes Summarizer',
    icon: '📧',
    description: 'Check unread emails, summarize key action items with Jac AI, and save a report in Apple Notes.',
    prompt: 'Check unread emails in my inbox every morning, summarize key points using AI, create a note in Apple Notes, and send a Mac notification.'
  },
  {
    title: 'File Organizer & MCP Extractor',
    icon: '📁',
    description: 'Monitor Downloads for new documents, categorize files, and organize them into specific folders.',
    prompt: 'Watch my Downloads folder for new files, use MCP tool to categorize documents, move invoices to Invoices folder, and log results.'
  },
  {
    title: 'Daily Calendar Briefing',
    icon: '⏰',
    description: 'Retrieve upcoming calendar events and deliver a daily morning notification schedule.',
    prompt: 'Every day at 8:00 AM, query Apple Calendar for todays events, summarize my schedule using Jac AI, and send a notification.'
  }
];

export default function AIScreen({
  onGenerateFromPrompt,
  isCompilingPrompt,
  onSwitchToWorkflow
}) {
  const [promptText, setPromptText] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!promptText.trim() || isCompilingPrompt) return;
    onGenerateFromPrompt(promptText);
  };

  const handleSelectPreset = (presetPrompt) => {
    setPromptText(presetPrompt);
  };

  return (
    <div className="flex-1 w-full h-full bg-[#050508] text-white flex flex-col overflow-hidden font-sans select-none">

      {/* Main AI Content */}
      <div className="flex-1 flex items-center justify-center p-8 overflow-y-auto">
        <div className="w-full max-w-3xl flex flex-col items-center text-center space-y-8">

          {/* Hero */}
          <div className="space-y-4">
            <div className="flex items-center justify-center gap-3 mb-2">
              <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-purple-500/20 to-indigo-500/20 border border-purple-500/20 flex items-center justify-center">
                <Bot className="w-5 h-5 text-purple-400" />
              </div>
            </div>
            <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight text-white">
              What should your agent build?
            </h1>
            <p className="text-sm sm:text-base text-zinc-400 max-w-xl mx-auto leading-relaxed">
              Describe any macOS automation workflow in plain English. The Jaclang compiler turns it into a visual node graph instantly.
            </p>
          </div>

          {/* Prompt Input */}
          <form onSubmit={handleSubmit} className="w-full space-y-4">
            <div className="relative rounded-3xl bg-zinc-950 border border-zinc-800 p-5 shadow-2xl focus-within:border-purple-500/50 transition-all group">
              <textarea
                rows={4}
                value={promptText}
                onChange={(e) => setPromptText(e.target.value)}
                placeholder="e.g. Every morning, check my unread emails, summarize the key points with AI, and save the summary as a note in Apple Notes..."
                className="w-full bg-transparent text-white text-sm placeholder-zinc-500 focus:outline-none resize-none leading-relaxed"
              />

              <div className="flex items-center justify-between pt-3 border-t border-zinc-900">
                <div className="flex items-center gap-2 text-[11px] text-zinc-600 font-mono">
                  <Cpu className="w-3 h-3" />
                  <span>Jaclang LLM Walkers</span>
                </div>

                <button
                  type="submit"
                  disabled={!promptText.trim() || isCompilingPrompt}
                  className={`flex items-center gap-2 px-6 py-2.5 rounded-2xl text-xs font-bold transition shadow-lg ${
                    !promptText.trim() || isCompilingPrompt
                      ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed'
                      : 'bg-white text-zinc-950 hover:bg-zinc-200 active:scale-95'
                  }`}
                >
                  {isCompilingPrompt ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin text-purple-600" />
                      <span>Compiling...</span>
                    </>
                  ) : (
                    <>
                      <Wand2 className="w-4 h-4 text-purple-600" />
                      <span>Generate Workflow</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </form>

          {/* Starter Templates */}
          <div className="w-full space-y-3 pt-2 text-left">
            <h3 className="text-[11px] font-bold uppercase tracking-widest text-zinc-500 px-1">
              Starter Templates
            </h3>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {PRESET_PROMPTS.map((preset, idx) => (
                <button
                  key={idx}
                  type="button"
                  onClick={() => handleSelectPreset(preset.prompt)}
                  className="p-4 rounded-2xl bg-zinc-950 border border-zinc-800 hover:border-zinc-700 hover:bg-zinc-900/60 transition text-left space-y-3 group shadow-sm flex flex-col justify-between"
                >
                  <div>
                    <div className="flex items-center gap-2 mb-2">
                      <span className="text-base">{preset.icon}</span>
                      <h4 className="text-xs font-bold text-white group-hover:text-purple-300 transition">
                        {preset.title}
                      </h4>
                    </div>
                    <p className="text-[11px] text-zinc-400 line-clamp-3 leading-relaxed">
                      {preset.description}
                    </p>
                  </div>
                  <div className="flex items-center text-[10px] font-semibold text-purple-400 group-hover:translate-x-1 transition-transform">
                    <span>Use this prompt</span>
                    <ArrowRight className="w-3 h-3 ml-1" />
                  </div>
                </button>
              ))}
            </div>
          </div>

        </div>

        {/* Back Button — pinned to bottom */}
        <button
          onClick={onSwitchToWorkflow}
          className="mt-6 flex items-center gap-2 text-xs font-semibold text-zinc-500 hover:text-white transition"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>Back to Canvas</span>
        </button>
      </div>
    </div>
  );
}
