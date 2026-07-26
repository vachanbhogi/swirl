# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
Primary users are non-technical founders, creators, and operators on macOS who need to automate desktop applications (Finder, Apple Notes, Mail, Calendar, System Controls) and API workflows using plain English prompts without writing code manually. Secondary users include Jaclang developers and hackathon evaluators who inspect and extend the generated native Jac code.

## Product Purpose
Swirl is a local-first desktop application that democratizes macOS automation and agentic workflows. It translates natural language instructions into visual Scratch-style workflow blocks, compiles them into executable Jaclang (`.jac`) code, and runs them via native Jac Walkers and Model Context Protocol (MCP) tool bridges. Success means non-technical users can build, inspect, and run complex desktop automations safely and reliably on their Mac.

## Positioning
Swirl is the first AI-native visual workflow desktop application that compiles visual block graphs directly into inspectable, executable Jaclang code. Unlike rigid proprietary automation tools (e.g. n8n, Zapier) or opaque LLM agents, Swirl provides bi-directional visual-to-code synchronization, full graph-walker observability, and local macOS desktop automation powered by Jaseci Labs' native graph primitives.

## Operating Context
- Local macOS desktop environment running as a signed Tauri v2 application.
- Interacts directly with Mac apps (Finder, Notes, Mail, Calendar, Safari/Chrome, Terminal) via AppleScript and system APIs.
- Integrates with Model Context Protocol (MCP) servers via stdio and HTTP JSON-RPC.
- Embedded Jaclang runtime executing Jac Walkers on local graph nodes.

## Capabilities and Constraints
- **Prompt-to-Workflow AI Compiler**: Natural language prompt bar generating visual node graphs via Jac `by llm()` primitives.
- **Scratch-Style Visual Canvas**: Drag-and-drop workflow builder supporting Trigger, LLM Transform, Mac App, MCP Tool, Condition, and Output blocks.
- **Bi-Directional Jac Code Sync**: Real-time code panel emitting clean `.jac` source code matching visual graph layout.
- **Live Walker Execution Inspector**: Real-time node illumination, log streaming, and output state tracking during walker traversal.
- **macOS Safety Guardrails**: Confirmation dialogs required prior to executing destructive filesystem or system shell actions.
- **Codebase Constraint**: Greater than 45% of total application logic implemented in native `.jac` files (`workflow_agent.jac`, `mac_control.jac`, `mcp_bridge.jac`, `code_generator.jac`).

## Brand Commitments
- **Name**: Swirl
- **Tagline**: AI Visual Workflow Desktop App & macOS MCP Control Center
- **Tone & Voice**: Empowering, approachable for non-technical users, clean, precise, and developer-respecting.
- **Design Philosophy**: High-craft Scratch-inspired visual blocks with modern dark mode aesthetic, vibrant status signals, and responsive micro-interactions.

## Evidence on Hand
- PRD document at [PRD.md](file:///Users/vachanbhogi/Documents/swirl/PRD.md)
- Multi-agent specifications at [AGENTS.md](file:///Users/vachanbhogi/Documents/swirl/AGENTS.md)
- Step-by-step setup guide at [STEP_BY_STEP_GUIDE.md](file:///Users/vachanbhogi/Documents/swirl/STEP_BY_STEP_GUIDE.md)
- Core Jac logic files: `main.jac`, `jac.toml`, and backend architecture files.

## Product Principles
1. **Visual Clarity, Code Transparency**: Make automation accessible through intuitive visual blocks while keeping generated Jac code inspectable and clean.
2. **Local-First & Privacy-Centered**: Run workflows locally on user hardware with explicit user permission for privileged system actions.
3. **Graph-Walker First**: Leverage Jaclang's native graph-walker semantics rather than state machines or arbitrary JSON configs.
4. **Resilient Automation**: Provide real-time execution feedback, clear error boundaries, and safe fallback mechanisms.

## Accessibility & Inclusion
- Desktop app UI designed with high-contrast visual node boundaries, clear focus states, legible typography, and structured keyboard navigation support.
