---
name: Swirl
description: AI Visual Workflow Desktop App & macOS MCP Control Center
colors:
  dark-bg: "#0A0D14"
  canvas-bg: "#0F1420"
  card-bg: "rgba(18, 24, 38, 0.85)"
  glass-bg: "rgba(22, 30, 48, 0.65)"
  glass-border: "rgba(255, 255, 255, 0.1)"
  trigger-purple: "#8B5CF6"
  ai-amber: "#F59E0B"
  mac-cyan: "#06B6D4"
  mcp-emerald: "#10B981"
  logic-indigo: "#6366F1"
  output-rose: "#F43F5E"
  jac-pink: "#EC4899"
  text-primary: "#F3F4F6"
  text-secondary: "#9CA3AF"
  text-muted: "#6B7280"
typography:
  display:
    fontFamily: "Outfit, sans-serif"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, sans-serif"
    fontWeight: 400
    lineHeight: 1.5
  code:
    fontFamily: "Fira Code, monospace"
    fontWeight: 500
    lineHeight: 1.6
rounded:
  sm: "6px"
  md: "10px"
  lg: "16px"
  pill: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  scratch-block:
    backgroundColor: "{colors.card-bg}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
  block-trigger:
    backgroundColor: "{colors.trigger-purple}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
  block-ai:
    backgroundColor: "{colors.ai-amber}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
  block-mac:
    backgroundColor: "{colors.mac-cyan}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
  block-mcp:
    backgroundColor: "{colors.mcp-emerald}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
  jac-badge:
    backgroundColor: "{colors.jac-pink}"
    textColor: "#ffffff"
    rounded: "{rounded.sm}"
    padding: "3px 8px"
---

# Design System: Swirl

## Overview

**Creative North Star: "Scratch for Agentic macOS Automation"**

Swirl pairs MIT Scratch's iconic visual block aesthetic with a sleek, dark glassmorphism desktop environment built for macOS. The interface presents non-technical creators with vibrant, tactile visual blocks that snap together logically while remaining fully inspectable as clean Jaclang (`.jac`) code for developers and evaluators.

The aesthetic balances playfulness with technical precision: category-coded Scratch blocks float above a subtle dot-grid canvas, connected by animated flowing wire paths. Smooth glassmorphic sidebars host the block palette, AI prompt input, live execution logs, and Jac code synchronization view.

**Key Characteristics:**
- **Tactile Scratch-Style Blocks**: Rounded, color-coded block nodes with visible snap-notch connectors and high-contrast borders.
- **Vibrant Functional Palette**: Distinct, rich color coding for block categories (Triggers, AI Transforms, Mac Apps, MCP Tools, Logic, Outputs).
- **Subtle Glassmorphism**: Deep obsidian panels (`#0A0D14`) with backdrop blur (`blur(16px)`), fine white rim borders, and dark dot-matrix canvas.
- **Live Walker Observability**: Glowing pulse highlights (`#10B981` / `#34D399`) and animated wire paths (`stroke-dasharray`) tracing active Jac Walker execution.

## Colors

The color system relies on high-contrast category accents against an obsidian glass backdrop, ensuring instant visual recognition for block types.

### Primary & Accent Palette
- **Jac Pink** (`#EC4899`): Used for Jaclang brand callouts, Jac code badges, and primary action highlights.
- **Trigger Purple** (`#8B5CF6` / border `#A78BFA`): Represents workflow triggers, schedule events, and entry points.
- **AI Amber** (`#F59E0B` / border `#FBBF24`): Represents LLM transforms, prompt operations, and reasoning nodes.
- **Mac Desktop Cyan** (`#06B6D4` / border `#67E8F9`): Represents native macOS app automation (Finder, Notes, Mail, Calendar, System).
- **MCP Emerald** (`#10B981` / border `#34D399`): Represents Model Context Protocol (MCP) server integrations and tool calls.
- **Logic Indigo** (`#6366F1` / border `#818CF8`): Represents conditional branches, loops, and decision gates.
- **Output Rose** (`#F43F5E` / border `#FB7185`): Represents execution outputs, notifications, and final deliverables.

### Neutral Surfaces
- **Obsidian Dark** (`#0A0D14`): Base desktop window background.
- **Canvas Navy** (`#0F1420`): Infinite workflow grid canvas background with `#FFFFFF1F` dot matrix pattern.
- **Glass Card** (`rgba(18, 24, 38, 0.85)`): Elevated sidebar and inspector panels.
- **Rim Border** (`rgba(255, 255, 255, 0.1)`): Subtle 1px structural glass borders.

### Named Rules
**The Category Color Rule.** A Scratch block's fill gradient and border must strictly reflect its functional category color token. Never mix category colors on a single block node.

## Typography

**Display Font:** Outfit (weights: 600, 700, 800)  
**Body Font:** Inter (weights: 400, 500, 600)  
**Code / Mono Font:** Fira Code (weights: 400, 500, 600)

**Character:** Friendly yet modern, pairing the rounded geometric clarity of Outfit for headings and Scratch block titles with crisp monospace readability in Fira Code for Jac source code generation.

### Hierarchy
- **Display** (Outfit 700, `1.5rem` / `24px`): Main window titles, app header, header brand badges.
- **Headline** (Outfit 600, `1.125rem` / `18px`): Section headers in property inspector and code view.
- **Title** (Outfit 600, `0.95rem` / `15px`): Scratch block titles and modal card headers.
- **Body** (Inter 400/500, `0.875rem` / `14px`): General UI labels, descriptions, and prompt bar text.
- **Code / Mono** (Fira Code 500, `0.85rem` / `13.5px`, line-height `1.6`): Jac code sync editor, execution logs, and raw JSON payloads.

## Layout

- **Three-Column Desktop Layout**: Left collapsible Scratch block palette (`260px`), central infinite workflow canvas with dot grid, right dual-tab Property Inspector & Jac Code View (`340px`).
- **Top AI Prompt Bar**: Floating glassmorphic text input bar (`max-width: 640px`) centered horizontally at top of canvas.
- **Scratch Block Canvas Grid**: 24px x 24px radial dot matrix (`radial-gradient(rgba(255, 255, 255, 0.12) 1px, transparent 1px)`).
- **Spatial Rhythm**: 8px grid spacing (`8px`, `16px`, `24px`) across all panel paddings and block ports.

## Elevation & Depth

Swirl relies on a hybrid model of glassmorphic elevation and glowing state accents. Surfaces use dark backdrop blur (`blur(16px)`) with subtle 1px white glass borders (`rgba(255, 255, 255, 0.1)`).

### Shadow & Glow Vocabulary
- **Scratch Block Resting**: `box-shadow: 0 8px 20px rgba(0, 0, 0, 0.4)`
- **Scratch Block Hover**: `box-shadow: 0 12px 28px rgba(0, 0, 0, 0.5)` with `transform: translateY(-2px)`
- **Selected Block Ring**: `box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.4), 0 12px 30px rgba(0, 0, 0, 0.6)`
- **Walker Traversal Glow**: `box-shadow: 0 0 20px #34D399, 0 0 45px rgba(52, 211, 153, 0.9)` (animated `@keyframes walkerGlow`)

### Named Rules
**The Tonal Depth Rule.** Flat dark background layers build up in opacity from base window (`#0A0D14`) to canvas grid (`#0F1420`) to floating glass cards (`rgba(18, 24, 38, 0.85)`). Higher z-index elements are lighter and more blurred.

## Shapes

- **Scratch Block Corners**: Rounded corners with `10px` border-radius and inset snap-notch connectors.
- **Port Nodes**: Circular circular ports (`14px` diameter, `50%` radius) with `2px` white border and dark center, expanding on hover to scale `1.35`.
- **Badges & Inputs**: Rounded `6px` radius for code tags; rounded `12px` or pill (`9999px`) radius for prompt inputs.
- **Modal Surfaces**: `16px` border-radius with `24px` backdrop blur and `rgba(0, 0, 0, 0.7)` deep drop shadow.

## Components

### Scratch Block (`.scratch-block`)
- **Structure**: Header bar with category icon & title, input parameters, interlocking port connectors (top/bottom execution flow, left/right data links).
- **Variants**: Category fill gradients (`block-cat-trigger`, `block-cat-ai`, `block-cat-mac`, `block-cat-mcp`, `block-cat-logic`, `block-cat-output`).
- **Interactions**: Drag cursor (`grab` -> `grabbing`), hover lift, selection glow outline (`#38BDF8`).

### Connection Wires (`.wire-path`)
- **Idle State**: Curved SVG bezier path with muted stroke and dashed animation (`stroke-dasharray: 6`).
- **Active Traversal**: Emerald glowing wire (`#34D399`) with accelerated pulse animation (`wirePulse 1s linear infinite`).

### AI Prompt Bar (`.prompt-input`)
- **Structure**: Glassmorphic input container with sparkle icon, natural language text input, and Jac generate trigger button (`Jac Pink`).
- **Focus**: Outer glow `0 0 0 2px rgba(139, 92, 246, 0.5)` with purple rim outline.

### Jac Code View (`.code-viewer-container`)
- **Structure**: Monospace editor panel with line numbers, syntax highlighting (Pink keywords `#F472B6`, Cyan builtins `#38BDF8`, Emerald strings `#34D399`, Gold functions `#FBBF24`, Purple nodes `#C084FC`), and copy `.jac` button.

## Do's and Don'ts

### Do's
- **DO** use exact category color tokens for all Scratch block types so users can visually classify nodes instantly.
- **DO** maintain smooth 60fps CSS transitions (`0.15s ease`) for block dragging, hovering, and wire port snapping.
- **DO** display live glowing pulse animations (`walkerGlow`) on the exact node currently being traversed by a Jac Walker.
- **DO** support dual-view toggle between Scratch visual blocks and generated Jac code.

### Don'ts
- **DON'T** use plain unstyled gray cards or square sharp corners for visual blocks.
- **DON'T** mix arbitrary font families outside of Outfit (display), Inter (body), and Fira Code (mono).
- **DON'T** obscure the visual graph canvas with heavy opaque modal dialogs—always maintain glass transparency.
- **DON'T** remove port connectors or snap notches from Scratch blocks.
