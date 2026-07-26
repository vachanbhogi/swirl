import React, { useState, useEffect } from 'react';

export default function NotchOverlay() {
  const [pulse, setPulse] = useState(true);

  useEffect(() => {
    const timer = setInterval(() => setPulse((p) => !p), 1500);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="h-screen w-screen bg-transparent flex items-start justify-center overflow-hidden font-sans select-none pt-1">
      <div className="flex items-center gap-2.5 px-4 py-2 bg-neutral-950/95 border border-white/15 rounded-full shadow-2xl backdrop-blur-xl text-neutral-100 transition-all duration-300 transform scale-100 hover:scale-105">
        {/* Animated glowing status indicator */}
        <div className="relative flex items-center justify-center">
          <div className={`absolute w-3.5 h-3.5 rounded-full bg-emerald-500/40 transition-transform duration-700 ${pulse ? 'scale-125 opacity-75' : 'scale-75 opacity-30'}`} />
          <div className="w-2 h-2 rounded-full bg-emerald-400 shadow-[0_0_8px_#34d399]" />
        </div>

        {/* Text */}
        <span className="font-semibold text-xs tracking-wide text-white">testing</span>

        {/* Sparkle Icon */}
        <span className="text-amber-400 text-xs font-bold">✨</span>
      </div>
    </div>
  );
}
