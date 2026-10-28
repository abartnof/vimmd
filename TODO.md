# VimMD Roadmap & Task Registry

This document tracks all active milestones, user requirements, and architectural tasks for the `vimmd` project.

---

## 1. In Progress
- [ ] **Milestone E: Finder 'Open With' Clean Launch (Suppress File Picker)**
  - [ ] When opening a file via Finder right-click ("Open With -> VimMD") or drag-and-drop, do NOT present the "Open File" picker sheet/dialog.
  - [ ] Defer launch picker check on runloop to allow Finder `application:openFile:` events to establish document controllers first.
  - [ ] Suppress picker if arguments contain files or if document was opened on launch.

---

## 2. Upcoming Milestones

### Milestone F: Viewport Zoom Controls in View Menu & Shortcuts
- [ ] **Zoom Commands in View Menu**:
  - `Zoom In` (`⌘+` / `⌘=` / `Cmd+=`): Increment magnification by +10% (e.g. up to 3.0x).
  - `Zoom Out` (`⌘-` / `Cmd+-`): Decrement magnification by -10% (e.g. down to 0.5x).
  - `Actual Size` (`⌘0` / `Cmd+0`): Reset magnification to 100% (1.0).
  - Enable `scrollView.allowsMagnification = true` with smooth pinch-to-zoom trackpad support.
  - Positioned in **View** menu alongside Wrap Lines and Appearance.

### Milestone G: Live Ex Command Line & Search Input in Status Bar
- [ ] **Live Interactive Command Display**:
  - When typing colon commands (`:`) or search patterns (`/`), display the command string live in the status bar at the bottom as keystrokes are typed (e.g. `:`, `:w`, `:wq`, `:%s/foo/bar/g`, `/search_term`).
  - Support backspace (`⌫`) deleting characters live from the command line.
  - On `<CR>`: Execute the command and display confirmation feedback or warnings.
  - On `<Esc>`: Clear the command line and restore normal mode status display.

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
- [x] Full Undo & Redo Subsystem (`97ab3eb`)
- [x] View Menu, Appearance Modes & Format-Aware Line Wrap Policy (`e51ea5d`)
- [x] Live In-Place Tabular Syntax Rendering for CSV & TSV (Milestone C)

