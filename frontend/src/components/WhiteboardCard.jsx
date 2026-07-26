import React, { useState, useRef } from 'react';
import { Move, ZoomIn, ZoomOut, Maximize2, Compass } from 'lucide-react';

export default function WhiteboardCard() {
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [isPanning, setIsPanning] = useState(false);
  const panRef = useRef({ startX: 0, startY: 0, initialX: 0, initialY: 0 });

  const handleMouseDown = (e) => {
    // Start canvas panning on drag
    setIsPanning(true);
    panRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      initialX: pan.x,
      initialY: pan.y
    };
  };

  const handleMouseMove = (e) => {
    if (!isPanning) return;
    const dx = e.clientX - panRef.current.startX;
    const dy = e.clientY - panRef.current.startY;
    setPan({
      x: panRef.current.initialX + dx,
      y: panRef.current.initialY + dy
    });
  };

  const handleMouseUp = () => {
    setIsPanning(false);
  };

  const handleWheel = (e) => {
    e.preventDefault();
    const zoomFactor = e.deltaY < 0 ? 1.05 : 0.95;
    setZoom((prevZoom) => Math.min(Math.max(prevZoom * zoomFactor, 0.4), 2.5));
  };

  const resetCamera = () => {
    setPan({ x: 0, y: 0 });
    setZoom(1);
  };

  return (
    <div className="absolute inset-0 pt-20 pl-6 pr-80 pb-6 pointer-events-auto select-none flex flex-col">
      <div className="w-full h-full rounded-3xl bg-white border border-neutral-300 shadow-2xl flex flex-col overflow-hidden relative">
        {/* Header / Canvas Control Bar */}
        <div className="h-11 px-6 bg-neutral-100 border-b border-neutral-200 flex items-center justify-between z-20">
          <div className="flex items-center gap-2 text-neutral-600">
            <Compass className="w-4 h-4 text-neutral-500" />
            <span className="text-xs font-mono font-medium text-neutral-700">Infinite Canvas</span>
            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-neutral-200 text-neutral-600">
              {Math.round(zoom * 100)}%
            </span>
          </div>

          {/* Camera Controls */}
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setZoom((z) => Math.min(z + 0.15, 2.5))}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Zoom In"
            >
              <ZoomIn className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={() => setZoom((z) => Math.max(z - 0.15, 0.4))}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Zoom Out"
            >
              <ZoomOut className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={resetCamera}
              className="p-1.5 rounded-lg text-neutral-600 hover:bg-neutral-200 transition"
              title="Reset View"
            >
              <Maximize2 className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Infinite Panning & Zoomable Canvas Area */}
        <div 
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
          onWheel={handleWheel}
          className={`flex-1 relative overflow-hidden bg-white cursor-grab ${
            isPanning ? 'cursor-grabbing' : ''
          }`}
        >
          {/* Pan & Zoom Grid Container */}
          <div 
            style={{
              transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
              transformOrigin: 'center center',
              backgroundPosition: `${pan.x}px ${pan.y}px`
            }}
            className="absolute inset-[-200%] canvas-grid-light transition-transform duration-75 ease-out flex items-center justify-center"
          >
            {/* Center Guidance Hint */}
            <div className="text-center space-y-2 pointer-events-none opacity-50">
              <p className="text-xs font-mono text-neutral-600 uppercase tracking-widest font-semibold">
                Infinite Workflow Canvas
              </p>
              <p className="text-xs text-neutral-400 max-w-sm">
                Click & drag to pan camera • Scroll wheel to zoom in & out
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
