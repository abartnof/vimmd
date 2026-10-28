# VimMD Roadmap & Task Registry

This document tracks all active milestones, user requirements, and architectural tasks for the `vimmd` project.

---

## 1. Completed
- [x] **Milestone E: Finder 'Open With' Clean Launch (Suppress File Picker)**
  - [x] When opening a file via Finder right-click ("Open With -> VimMD") or drag-and-drop, do NOT present the "Open File" picker sheet/dialog.
  - [x] Defer launch picker check on runloop to allow Finder `application:openFile:` events to establish document controllers first.
  - [x] Suppress picker if arguments contain files or if document was opened on launch.
- [x] **Milestone F: Viewport Zoom Controls in View Menu & Shortcuts**
  - [x] `Zoom In` (`⌘+` / `⌘=` / `Cmd+=`): Increment magnification by +10% (e.g. up to 3.0x).
  - [x] `Zoom Out` (`⌘-` / `Cmd+-`): Decrement magnification by -10% (e.g. down to 0.5x).
  - [x] `Actual Size` (`⌘0` / `Cmd+0`): Reset magnification to 100% (1.0).
  - [x] Enable `scrollView.allowsMagnification = true` with smooth pinch-to-zoom trackpad support.
  - [x] Positioned in **View** menu alongside Wrap Lines and Appearance.
- [x] **Milestone G: Live Ex Command Line & Search Input in Status Bar**
  - [x] When typing colon commands (`:`) or search patterns (`/`), display the command string live in the status bar at the bottom as keystrokes are typed (e.g. `:`, `:w`, `:wq`, `:%s/foo/bar/g`, `/search_term`).
  - [x] Support backspace (`⌫`) deleting characters live from the command line.
  - [x] On `<CR>`: Execute the command and display confirmation feedback or warnings.
  - [x] On `<Esc>`: Clear the command line and restore normal mode status display.
- [x] **Milestone H: Save Confirmation Chip & Dirty Exit Warning**
  - [x] **Transient 'Saved' Chip in Status Bar**:
    - [x] When document is saved (`:w`, `:wq`, `ZZ`, `Cmd+S`, Cocoa save), display a prominent 'Saved' pill/chip badge (`✓ Saved` with subtle green accent tint and rounded corners) in status bar for ~2 seconds before fading out.
    - [x] Accessible and inspectable via `savedChipView` and `isSavedChipVisible`.
  - [x] **Unsaved Changes Exit Warning Sheet & Vim Blocking**:
    - [x] Set `autosavesInPlace` to `false` to prevent silent overwrites and bypass of close confirmation.
    - [x] Synchronize `session.isDirty` with AppKit `updateChangeCount(.changeDone)` / `updateChangeCount(.changeCleared)`.
    - [x] Vim path (`:q`, `:qa`): Blocks close when dirty and displays `[Warning] E37: No write since last change (add ! to override)` in warning style.
    - [x] macOS path (`Cmd+W`, `Cmd+Q`, window close button): Prompts standard native alert save sheet when document is edited, preventing accidental data loss.

---

## 2. Upcoming Milestones

### Milestone I: Typography Hierarchy (Monospace Default for Non-Markdown)
- [ ] **Format-Aware Typography Hierarchy**:
  - **Markdown (`.md`)**: Rich hybrid typography (proportional SF Pro for headers, body text, bold, italics, and lists; monospaced SF Mono for code spans, tables, and frontmatter).
  - **All Other Formats (`.txt`, `.csv`, `.tsv`, `.sh`, `.json`, etc.)**: Default to native Monospaced System Font (SF Mono, 13pt).

### Milestone J: Operator-Pending Inner Text Objects (`di'`, `ci'`, `yi'`)
- [ ] **Delete Inner Text Objects (`di...`)**:
  - `di'`: Delete content inside single quotes (`'...'`) without deleting quotes.
  - `di"`: Delete content inside double quotes (`"..."`) without deleting quotes.
  - `di(` / `di)` / `dib`: Delete content inside parentheses (`(...)`).
  - `di[` / `di]`: Delete content inside square brackets (`[...]`).
  - `di<` / `di>`: Delete content inside angle brackets (`<...>`).
  - `di{` / `di}` / `diB`: Delete content inside braces (`{...}`).
- [ ] **Change Inner Text Objects (`ci...`)**:
  - `ci'`, `ci"`, `ci(`, `ci)`, `cib`, `ci[`, `ci]`, `ci<`, `ci>`, `ci{`, `ci}`, `ciB`: Delete content inside enclosing pairs and immediately transition to Insert mode at insertion point.
- [ ] **Yank Inner Text Objects (`yi...`)**:
  - `yi'`, `yi"`, `yi(`, `yi)`, `yib`, `yi[`, `yi]`, `yi<`, `yi>`, `yi{`, `yi}`, `yiB`: Yank content inside enclosing pairs to clipboard without modifying buffer.

### Milestone K: Vim `:sort` Command Subsystem
- [ ] **Alphabetical and Numerical Line Sorting (`:sort`)**:
  - `:sort`: Lexicographically sort lines across the entire buffer (or within active visual range `:'<,'>sort`).
  - `:sort!`: Reverse/descending sort order.
  - `:sort i`: Case-insensitive lexicographical sorting.
  - `:sort u`: Deduplicate identical adjacent lines (unique filter).
  - `:sort n`: Numeric sorting (evaluating leading or embedded integers).
  - Support range prefixes: `:1,10sort`, `:'<,'>sort` from visual line mode.
  - Seamless undo/redo tracking and line index table re-indexing with differential line deltas.

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

