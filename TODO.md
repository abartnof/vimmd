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
- [x] **Milestone I: Typography Hierarchy (Monospace Default for Non-Markdown)**
  - [x] **Markdown (`.md`, `.markdown`)**: Rich hybrid typography (proportional SF Pro for headers, body text, bold, italics, and lists; monospaced SF Mono 13pt for code spans, tables, code fences, and frontmatter).
  - [x] **All Other Formats (`.txt`, `.csv`, `.tsv`, `.sh`, `.json`, `.py`, `.c`, `.swift`, `.yaml`, etc., and untitled non-markdown documents)**: Default to native Monospaced System Font (SF Mono 13pt, `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)`) with `NSColor.textColor`.
  - [x] **Zero Markdown Concealment Leakage**: Plain text documents have 100% SF Mono 13pt without header resizing or delimiter hiding, even if text contains markdown tokens (`#`, `*`, `**`, `` ` ``).
  - [x] **Dynamic Format Switching & Typing**: Seamless typography synchronization on syntax mode switches and delta typing.
- [x] **Milestone J: Operator-Pending Inner Text Objects (`di'`, `ci'`, `yi'`)**
  - [x] **Delete Inner Text Objects (`di...`)**:
    - `di'`: Delete content inside single quotes (`'...'`) without deleting quotes.
    - `di"`: Delete content inside double quotes (`"..."`) without deleting quotes.
    - `di(` / `di)` / `dib`: Delete content inside parentheses (`(...)`).
    - `di[` / `di]`: Delete content inside square brackets (`[...]`).
    - `di<` / `di>`: Delete content inside angle brackets (`<...>`).
    - `di{` / `di}` / `diB`: Delete content inside braces (`{...}`).
  - [x] **Change Inner Text Objects (`ci...`)**:
    - `ci'`, `ci"`, `ci(`, `ci)`, `cib`, `ci[`, `ci]`, `ci<`, `ci>`, `ci{`, `ci}`, `ciB`: Delete content inside enclosing pairs and immediately transition to Insert mode at insertion point.
    - Single cohesive undo group encompassing change + insert typing.
  - [x] **Yank Inner Text Objects (`yi...`)**:
    - `yi'`, `yi"`, `yi(`, `yi)`, `yib`, `yi[`, `yi]`, `yi<`, `yi>`, `yi{`, `yi}`, `yiB`: Yank content inside enclosing pairs to clipboard without modifying buffer.
    - Restores cursor to starting position.
  - [x] Single-line and multiline nested pairs support, empty pair safety, and `<Esc>` cancellation.
- [x] **Milestone L: Live Search Status Bar Feedback & Navigation Pipeline (`/`, `n`, `N` / `p`)**
  - [x] **Bottom-Left Search Bar & Command Prompt UI (`/`)**:
    - When typing `/` or `:` in Command mode, hide `-- COMMAND --` and position the prompt directly at bottom-left (`x = 8`) in monospaced bold font.
    - Live-stream keystrokes into `session.commandLineBuffer` and immediately display `/query` starting from `x = 8`.
    - Seamlessly restore `-- NORMAL --` at `x = 8` and status message label at `x = 155` upon leaving Command mode.
  - [x] **Search Execution & Viewport Auto-Centering**:
    - On `<CR>`: Execute search forward, jump cursor to match, display `/<query>` in status bar, and scroll viewport to ensure matched occurrence is clearly visible.
    - If pattern is not found, display prominent warning: `Pattern not found: <pattern>`.
    - If empty search without previous pattern, display `E35: No previous regular expression`.
  - [x] **Subsequent Search Navigation (`n` / `N` / `p`)**:
    - `n`: Jump to next search occurrence forward and auto-scroll to caret.
    - `N`: Jump to previous search occurrence backward and auto-scroll to caret.
    - `p`: When yank buffer is empty and search has occurred, navigate backward to previous match (matching user expectations without breaking paste when yank buffer is populated).
    - Retain and display active search query pattern across navigation.

---

## 2. Upcoming Milestones

### Milestone K: Vim `:sort` Command Subsystem
- [ ] **Alphabetical and Numerical Line Sorting (`:sort`)**:
  - `:sort`: Lexicographically sort lines across the entire buffer (or within active visual range `:'<,'>sort`).
  - `:sort!`: Reverse/descending sort order.
  - `:sort i`: Case-insensitive lexicographical sorting.
  - `:sort u`: Deduplicate identical adjacent lines (unique filter).
  - `:sort n`: Numeric sorting (evaluating leading or embedded integers).
  - Support range prefixes: `:1,10sort`, `:'<,'>sort` from visual line mode.
  - Seamless undo/redo tracking and line index table re-indexing with differential line deltas.

### Milestone M: Excel-Style Spreadsheet View for CSV & TSV (Gridlines, Dynamic Sizing, Wrap, Freeze Panes)
- [ ] **Excel / Numbers Grid Styling**:
  - Replace rainbow column coloring with clean, professional neutral typography and subtle header shading.
  - Render crisp horizontal and vertical grey gridlines separating rows and columns (adapting to macOS Light/Dark appearance).
- [ ] **Dynamic Row & Column Addition As You Type**:
  - **Dynamic Row Insertion (`o`, `O`, `<CR>`)**:
    - Opening a new row in a tabular file automatically aligns to the table schema ($N-1$ delimiter placeholders) so new rows immediately match the column count of the spreadsheet.
  - **Dynamic Column Addition (`,` / `<Tab>`)**:
    - Typing a delimiter at the end of a row or header seamlessly adds a new column to the table.
    - Grid columns, cell boundaries, and vertical gridlines dynamically expand in real-time as content is typed.
  - **Fluid Caret Synchronization**:
    - Caret tracking accurately stays centered inside the active cell while column widths expand dynamically under live keystrokes.
- [ ] **Column Widths & View Menu 'Text Wrap'**:
  - Add `Text Wrap` (or `Wrap Table Cells`) option to the **View** menu for tabular documents.
  - **Wrap OFF (Default)**: Each column expands so its width accommodates its longest entry (`max(cellContentWidth) + padding`), keeping columns vertically aligned across arbitrarily wide datasets.
  - **Wrap ON**: Apply a sensible default column width (e.g. 240pt / 30 chars), wrapping multi-word content within cell boundaries.
  - Robust horizontal scrolling support for wide tables (dozens/hundreds of columns) without horizontal truncation.
- [ ] **Freeze Panes & Dedicated 'Spreadsheet' View Menu Section**:
  - In the **View** menu, add a dedicated `Spreadsheet` section (or section with separators) containing:
    - `View -> Freeze First Row` (checkable)
    - `View -> Freeze First Column` (checkable)
    - `View -> Wrap Table Cells` (checkable)
  - **Format-Aware Validation**: These menu items are dynamically enabled ONLY when the active document is a CSV or TSV (`isTabularDocument == true`). For all other file types (Markdown, plain text, shell scripts, JSON, etc.), they automatically grey out via `validateUserInterfaceItem`.
  - State persistence and dynamic viewport layout integration.
- [ ] **Interactive Header Copy Gestures (Mouse Hover & Quick Click)**:
  - **Column A Hover (Row Selector)**: Hovering over column A morphs the cursor into a rightward arrow (`→`). Clicking flashes the targeted row with a subtle highlight animation and automatically copies the row's values to the macOS clipboard.
  - **Row 1 Hover (Column Selector)**: Hovering over row 1 morphs the cursor into a downward arrow (`↓`). Clicking flashes the entire column vertically with a subtle highlight animation and automatically copies the column's values (newline-delimited) to the macOS clipboard.
  - Displays a transient status confirmation (e.g. `Row 5 copied to clipboard` / `Column 'Price' copied to clipboard`).
- [ ] **Vim Editing & Plain-Text Integrity**:
  - Retain raw UTF-8 comma/tab separated text representation on disk with zero proprietary metadata.
  - Full modal navigation (`h`, `j`, `k`, `l`, `w`, `b`, `$`, `0`, `f`, `t`) and editing in grid cells.

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

