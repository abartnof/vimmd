# VimMD Roadmap & Task Registry

This document tracks all active milestones, user requirements, and architectural tasks for the `vimmd` project.

---

## 1. In Progress
- [x] **Full Undo & Redo Subsystem** (`97ab3eb`)
- [ ] **View Menu, Appearance Modes & Line Wrap Policy**
  - [x] Multi-tier snapshot history stack in C engine (`struct VimUndoState` in `VimDocumentContext`).
  - [x] Snapshot boundaries captured before buffer mutations (`dd`, `dw`, `d$`, `d0`, `x`, `s`, `p`, `P`, `J`, `:%s`, and Insert mode sessions).
  - [x] Vim keys: `u` (Undo) and `<C-r>` (`\x12`, Redo).
  - [x] Ex commands: `:u` / `:undo` and `:redo`.
  - [x] macOS keys: `Cmd+Z` (Undo) and `Cmd+Shift+Z` (Redo).
  - [x] AppKit `undoManager` / `undo(_:)` / `redo(_:)` responder actions.
  - [x] Truncation of redo history on new edits; zero memory leaks on deallocation.
  - [x] Real-time view, status bar, and line number ruler sync on undo/redo.

---

## 2. Upcoming Milestones

### Milestone A: View Menu, Appearance Modes & Line Wrap Toggle
- [ ] **View Menu in macOS Menu Bar**:
  - Position: `[VimMD] [File] [Edit] [View] [Window] [Help]`.
  - **Appearance Submenu**:
    - `✓ Match System` (dynamically follows macOS Dark/Light Mode).
    - `Light` (forces `.aqua`).
    - `Dark` (forces `.darkAqua`).
  - **Wrap Lines Toggle (`⌥⌘W` / `Cmd+Option+W`)**:
    - Checked: Soft line wrapping enabled within viewport width.
    - Unchecked: Horizontal scrolling enabled, lines do not wrap.

### Milestone B: Line Wrap Defaults & Preference Persistence
- [ ] **Format-Specific Defaults**:
  - `.csv` and `.tsv` files: Default to **Line Wrap OFF** (`wrapLines = false`) with horizontal scroller active.
  - All other file formats (`.md`, `.txt`, `.sh`, `.json`, etc.): Default to previous user usage (persisted via `UserDefaults.standard`).

### Milestone C: Live In-Place Rendering for CSV & TSV
- [ ] **Real-Time Tabular Syntax Rendering**:
  - Live column-aware syntax styling for `.csv` and `.tsv` while typing and viewing (in both Normal and Insert modes).
  - Row 1 highlighted as table header with bold typography.
  - Column differentiation: Alternating subtle column tints/colors.
  - Delimiter styling: Subtle dimmed commas (`,`) and tabs (`\t`) so data cells stand out.
  - Quotes and escaped strings handled cleanly in CSV parsing.

### Milestone D: 36 Synthetic CUJ Test Fleet & Keystroke Deduplication
- [ ] **36 End-to-End Synthetic User Journeys**:
  - 6 Markdown authoring CUJs (tables, task lists, formatting).
  - 6 Code & config CUJs (Shell, Python, JSON, TSV/CSV).
  - 6 Precision motion & search CUJs (`0`, `^`, `$`, `w`, `b`, `e`, `ge`, `f`, `t`, counts, `/`, `n`, `N`).
  - 6 Operator mutation CUJs (`dd`, `dw`, `d$`, `d0`, `yy`, `p`, `cc`, `cw`, `x`, `s`, `r`, `J`).
  - 6 Visual text object CUJs (`vi'`, `vi"`, `vi(`, `vi[`, `vi<`, `vi{`, `v...d`, `V...y`).
  - 6 History & system pipeline CUJs (undo/redo, clipboard exchange, `:w`, `ZZ`, `:%s`).
- [ ] **Deduplicated Keystroke Verification Matrix**:
  - Extract and deduplicate every key/chord pressed across all 36 journeys.
  - Verify every single key works with 100% fidelity under character-by-character streaming input.

---

## 3. Completed Milestones
- [x] Initial Project Skeleton & C Bridge Harness (`58aff93`)
- [x] Unicode Coordinate Resolver & Differential Line Index Table (`07e059e`)
- [x] Multi-Window C Context Switcher & Line Delta Dispatch (`8b4d595`)
- [x] In-Place Markdown Syntax Concealment & NSTextInputClient (`8e00b66`)
- [x] Native Document Lifecycle & App Packaging (`fd06467`)
- [x] Build Optimizations (`-Oz`, `-Osize`, `-dead_strip`, 60 KB bundle) (`427cfee`)
- [x] Open Line Delta Corrections (`8d7ad2d`)
- [x] ObjC Runtime Exposure & Default File Picker (`fa9fa6f`)
- [x] Complete Vim System Actions (`:w`, `:w!`, `:wa`, `:q`, `:q!`, `:qa`, `:qa!`, `:wq`, `:x`, `ZZ`, `ZQ`, `:e!`) (`f001b9a`)
- [x] Lossy UTF-8 Decoding & Document Extensions Expansion (`9904a13`, `16eb986`)
- [x] Automated CUJ Trial for Rich Formats (`fb75f63`)
- [x] First Responder Keyboard Focus & Hotkey Guard (`49462cb`)
- [x] Status Bar Warnings (`E32`, write feedback) & Permanent Markdown Typography (`e0f92a5`)
- [x] Dynamic Viewport Scrolling & Caret Auto-Scroll (`65d3a2a`)
- [x] Core 80/20 Vim Motions & Inner Text Objects (`vi'`, `vi"`, `vi(`, `vi[`, `vi<`, `vi{`) (`23fbcf9`)
- [x] Row Number Gutter Pane (`LineNumberRulerView`) with Copy Isolation (`c7c459f`)
- [x] Bidirectional macOS Clipboard Integration (`NSPasteboard.general`) (`c7c459f`)
