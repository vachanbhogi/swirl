import React, { useState } from 'react';
import Navbar from './components/Navbar';
import WhiteboardCard from './components/WhiteboardCard';
import CodeBlockPalette from './components/CodeBlockPalette';

export default function App() {
  const [isExecuting, setIsExecuting] = useState(false);
  const [showCodeView, setShowCodeView] = useState(false);

  return (
    <div className="h-screen w-screen bg-black text-neutral-100 relative overflow-hidden font-sans">
      {/* Floating Navbar */}
      <Navbar 
        isExecuting={isExecuting}
        showCodeView={showCodeView}
        setShowCodeView={setShowCodeView}
        onRunWorkflow={() => setIsExecuting(true)}
        onClearCanvas={() => setIsExecuting(false)}
      />

      {/* Main Workspace: Whiteboard Grid Canvas + Right Code Block Palette */}
      <main className="h-full w-full relative">
        <WhiteboardCard />
        <CodeBlockPalette />
      </main>
    </div>
  );
}


