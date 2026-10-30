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
- [x] **Milestone K: Vim `:sort` Command Subsystem**
  - [x] **Alphabetical and Numerical Line Sorting (`:sort`)**:
    - [x] `:sort`: Lexicographically sort lines across the entire buffer (or within active visual range `:'<,'>sort`).
    - [x] `:sort!`: Reverse/descending sort order.
    - [x] `:sort i`: Case-insensitive lexicographical sorting.
    - [x] `:sort u`: Deduplicate identical adjacent lines (unique filter).
    - [x] `:sort n`: Numeric sorting (evaluating leading or embedded integers).
    - [x] Support range prefixes: `:1,10sort`, `:'<,'>sort` from visual line mode.
    - [x] Seamless undo/redo tracking and line index table re-indexing with differential line deltas.
- [x] **Milestone M: Excel-Style Spreadsheet View for CSV & TSV (Gridlines, Dynamic Sizing, Wrap, Freeze Panes)**
  - [x] **Excel / Numbers Grid Styling**:
    - Replace rainbow column coloring with clean, professional neutral typography and subtle header shading.
    - Render crisp horizontal and vertical grey gridlines separating rows and columns (adapting to macOS Light/Dark appearance).
  - [x] **Dynamic Row & Column Addition As You Type**:
    - **Dynamic Row Insertion (`o`, `O`, `<CR>`)**:
      - Opening a new row in a tabular file automatically aligns to the table schema ($N-1$ delimiter placeholders) so new rows immediately match the column count of the spreadsheet.
    - **Dynamic Column Addition (`,` / `<Tab>`)**:
      - Typing a delimiter at the end of a row or header seamlessly adds a new column to the table.
      - Grid columns, cell boundaries, and vertical gridlines dynamically expand in real-time as content is typed.
    - **Fluid Caret Synchronization**:
      - Caret tracking accurately stays centered inside the active cell while column widths expand dynamically under live keystrokes.
  - [x] **Column Widths & View Menu 'Text Wrap'**:
    - Add `Text Wrap` (or `Wrap Table Cells`) option to the **View** menu for tabular documents.
    - **Wrap OFF (Default)**: Each column expands so its width accommodates its longest entry (`max(cellContentWidth) + padding`), keeping columns vertically aligned across arbitrarily wide datasets.
    - **Wrap ON**: Apply a sensible default column width (e.g. 240pt / 30 chars), wrapping multi-word content within cell boundaries.
    - Robust horizontal scrolling support for wide tables (dozens/hundreds of columns) without horizontal truncation.
  - [x] **Freeze Panes & Dedicated 'Spreadsheet' View Menu Section**:
    - In the **View** menu, add a dedicated `Spreadsheet` section (or section with separators) containing:
      - `View -> Freeze First Row` (checkable)
      - `View -> Freeze First Column` (checkable)
      - `View -> Wrap Table Cells` (checkable)
    - **Format-Aware Validation**: These menu items are dynamically enabled ONLY when the active document is a CSV or TSV (`isTabularDocument == true`). For all other file types (Markdown, plain text, shell scripts, JSON, etc.), they automatically grey out via `validateUserInterfaceItem`.
    - State persistence and dynamic viewport layout integration.
  - [x] **Interactive Header Copy Gestures (Mouse Hover, Click & Drag Range)**:
    - **Column A Hover & Drag (Row Selector)**:
      - Hovering over column A morphs the cursor into a rightward arrow (`→`).
      - Clicking copies the row's values to the macOS clipboard with a subtle highlight flash animation.
      - **Multi-Row Dragging**: Clicking and dragging down/up across column A selects a range of rows (e.g. rows 3–8), flashes the row range on mouse-up, and copies all selected rows to the clipboard.
      - Displays transient status feedback (e.g. `Row 5 copied to clipboard` or `Rows 3–8 copied to clipboard`).
    - **Row 1 Hover & Drag (Column Selector)**:
      - Hovering over row 1 morphs the cursor into a downward arrow (`↓`).
      - Clicking copies the column's values (newline-delimited) to the macOS clipboard with a subtle vertical highlight flash animation.
      - **Multi-Column Dragging**: Clicking and dragging left/right across row 1 selects a range of columns (e.g. columns B–D), flashes the column range on mouse-up, and copies all selected columns across all rows to the clipboard.
      - Displays transient status feedback (e.g. `Column 'Price' copied to clipboard` or `Columns B–D copied to clipboard`).
  - [x] **Vim Editing & Plain-Text Integrity**:
    - Retain raw UTF-8 comma/tab separated text representation on disk with zero proprietary metadata.
    - Full modal navigation (`h`, `j`, `k`, `l`, `w`, `b`, `$`, `0`, `f`, `t`) and editing in grid cells.
- [x] **Milestone D: 36 Synthetic CUJ Test Fleet & Keystroke Deduplication Matrix**
  - [x] **36 End-to-End Synthetic User Journeys**:
    - [x] 6 Markdown authoring CUJs (tables, task lists, formatting, frontmatter, headers H1–H6, code fences).
    - [x] 6 Code & config CUJs (Shell, Python, JSON, YAML, CSV, TSV).
    - [x] 6 Precision motion & search CUJs (`0`, `^`, `$`, `w`, `b`, `e`, `ge`, `f`, `t`, counts, `/`, `n`, `N`, `p`).
    - [x] 6 Operator mutation CUJs (`dd`, `dw`, `d$`, `d0`, `yy`, `p`, `P`, `cc`, `cw`, `x`, `s`, `r`, `J`).
    - [x] 6 Visual text object CUJs (`vi'`, `vi"`, `vi(`, `vi[`, `vi<`, `vi{`, `di'`, `ci"`, `yi(`, `di[`, `ci<`, `ci{`, `v...d`, `V...y`).
    - [x] 6 History & system pipeline CUJs (undo/redo cycles `u` and `Ctrl-R`, persistence `:w`, `ZZ`, `:%s`, `:sort` modes, freeze panes, drag copy).
  - [x] **Deduplicated Keystroke Verification Matrix**:
    - [x] Extract and deduplicate every key/chord pressed across all 36 journeys via `KeystrokeRecorder`.
    - [x] Verify all 100 unique keys with 100% fidelity under character-by-character streaming input.
    - [x] Print console matrix report summarizing 36/36 CUJs, total keystrokes, and category breakdown.

---

## 2. Active Milestones
- [x] **Milestone N: High-Contrast White Cursor & Native SF Symbol App Icon**
  - [x] **High-Contrast Mouse Cursors (White with Black Outline)**:
    - [x] Design custom high-visibility `downwardArrowCursor` (↓) and `rightwardArrowCursor` (→) rendered with crisp `NSColor.white` fill and `NSColor.black` 1.5pt border outline, matching standard macOS cursor contrast.
    - [x] Position hotspots accurately at the arrow tips for pixel-perfect hover precision over column A and row 1.
    - [x] Maintain flawless visibility across both Light Mode and Dark Mode backgrounds.
  - [x] **Native SF Symbol App Icon (`v.circle`)**:
    - [x] Adopt `v.circle` (`NSImage(systemSymbolName: "v.circle", accessibilityDescription: "VimMD")`) as the official lightweight app icon without binary bloat.
    - [x] Set `NSApplication.shared.applicationIconImage` dynamically at launch in `AppDelegate`.
    - [x] Package multi-resolution `AppIcon.icns` in `VimMD.app/Contents/Resources/` and register `CFBundleIconFile` in `Info.plist` for Finder and Dock support.

- [x] **Milestone O: Tabular Modal Input & First Responder Parity (Vim Commands in Spreadsheets)**
  - [x] **First Responder & Mouse Down Fix**: Ensure clicking anywhere in a tabular document (including row 0 headers and column A cells) properly activates `firstResponder` on `VimMDTextView`, positions the Vim caret at the clicked cell, and allows subsequent typing without swallowing events.
  - [x] **Full Modal Parity**: Verify that all standard Vim commands work identically in tabular documents:
    - Navigation: `h`, `j`, `k`, `l`, `w`, `b`, `e`, `ge`, `0`, `^`, `$`, `gg`, `G`, `f`, `t`.
    - Mutations: `x`, `s`, `r`, `cw`, `cc`, `c$`, `dd`, `dw`, `d$`, `yy`, `yw`, `p`, `P`, `J`.
    - Modal Transitions: `i`, `I`, `a`, `A`, `o`, `O` with automatic tabular delimiter alignment.
    - History: `u` (undo) and `Ctrl-R` (redo) maintaining intact spreadsheet structure.
    - Ex Commands: `:w`, `:q`, `:sort`, `:%s/find/replace/g`, `/search`.

- [x] **Milestone R: Spreadsheet Cell Click Caret to First Position**
  - [x] If a user clicks anywhere on a cell in a spreadsheet (`.csv`, `.tsv`), the cursor immediately goes to the first position of that cell (matching Excel/spreadsheet standard click-to-select-cell behavior and avoiding mid-word, delimiter, or kerning gap misalignment).
  - [x] Ensure click handling works accurately for all cells: header cells (Row 0), Column A cells, interior cells, empty cells (`,,`), quoted cells (`"..."`), and trailing cells.
  - [x] Full first-responder activation and synchronization with Vim engine cursor coordinates.

- [x] **Milestone P: Fleet of UX Researcher Subagents (Automated End-to-End GUI Simulation)**
  - [x] **Spreadsheet UX Researcher Subagent (`.csv`, `.tsv`)**:
    - Simulates AppKit GUI interactions on real tabular files: window activation, cell clicking, cursor navigation, in-cell typing, column/row additions, menu toggles (`Freeze First Row`, `Freeze First Column`, `Wrap Table Cells`), and clipboard copy gestures (`scripts/spreadsheet_ux_trial.swift`).
  - [x] **Markdown UX Researcher Subagent (`.md`, `.markdown`)**:
    - Simulates AppKit GUI interactions on Markdown files: live editing, header formatting, list editing, code block toggles, table alignment, and syntax concealment transitions (`scripts/markdown_ux_research.swift`).
  - [x] **Plain Text & Code UX Researcher Subagent (`.txt`, `.sh`, `.json`, `.py`)**:
    - Simulates AppKit GUI interactions on plain text and code files: monospace typography verification, zoom shortcuts (`Cmd+=`, `Cmd+-`, `Cmd+0`), live search prompts (`/query`), dirty save warnings, repeat find motions (`;`, `,`), and `:sort` (`scripts/plaintext_code_ux_trial.swift`).

- [x] **Milestone S: Cell-Relative Vertical Navigation in Spreadsheets (`j`, `k`, Up/Down Arrows)**
  - [x] In a spreadsheet (`.csv`, `.tsv`), moving up (`k` / Up Arrow) or down (`j` / Down Arrow) remains strictly locked relative to the current cell column index $C$.
  - [x] The cursor does not drift left or right into adjacent cells due to differing character lengths of fields on adjacent rows (e.g. moving between a 2-char number cell and a 40-char title cell).
  - [x] When moving between rows $R$ and $R \pm 1$, compute target cell column index $C$ and position caret at the start of cell $C$ in the target row.
  - [x] Guards against pending command hijacking (`!session.hasPendingCommand`) so `fj`, `rj`, `gj`, and `dj` maintain command integrity.
  - [x] Standard character-offset vertical navigation is strictly preserved for non-tabular files (Markdown, Plain Text, and Code).

- [x] **Milestone T: Top-Left Window Positioning on Screen & Viewport Scroll Origin**
  - [x] When opening any document, position the `NSWindow` at the top-left of the user's primary display screen (`NSScreen.main?.visibleFrame`), cascading cleanly.
  - [x] Ensure wide Markdown files (and wide code/tables) initialize with the scroll view origin at `(0, 0)` (top-left) so the user never lands on the top-right of wide documents.
  - [x] Verified with ultra-wide (50k+ char), multi-monitor, empty file, and rapid-reload test coverage.

- [x] **Milestone U: Intra-Cell Column Offset Preservation on Vertical Spreadsheet Navigation**
  - [x] When navigating vertically (`j`, `k`, Up/Down arrows) across rows in a spreadsheet (`.csv`, `.tsv`), respect Vim's column position rules **within the cell**.
  - [x] If the cursor is at character offset $X$ within cell column $C$ on row $i$ (e.g. the 2nd character), moving to row $i \pm 1$ lands at character offset $X$ within cell $C$ of the target row.
  - [x] If the target cell is shorter than $X$, clamp cleanly to the end of that cell (e.g. at end of a 4-char cell moving to a 3-char cell lands at end; moving to a 10-char cell preserves offset 4).
  - [x] Replaces the previous behavior that always snapped to the 1st position of the cell while keeping mouse clicks at position 1.

- [x] **Milestone V: Asynchronous Layout Viewport & Cursor Top-Left Pinning on Wide Documents**
  - [x] When opening a wide document (wide Markdown, tables, code), guarantee the cursor is at Line 1, Col 1 (top-left) and the viewport's visible scroll rect is anchored at `(0, 0)` so the top-left area is guaranteed visible.
  - [x] Address AppKit asynchronous post-layout runloop passes (`viewDidMoveToWindow`, initial layout pass, `DispatchQueue.main.async`) that previously caused wide unwrapped lines to shift the clip view horizontally to the right.

- [x] **Milestone W: Ruler-Aware Viewport Alignment & Word End Operators (`de`, `ce`, `ye`)**
  - [x] **Ruler-Aware Viewport Alignment**:
    - [x] Fix `resetScrollToTopLeft()` and `pinViewportToTopLeft()` in `VimMDTextView`: account for `LineNumberRulerView` thickness (`-rulerThickness`) and use AppKit's native `scrollToBeginningOfDocument(nil)` / `scrollRangeToVisible(NSRange(location: 0, length: 0))`.
    - [x] Ensures navigating up to row 1 from row 2 never clips or hides the 1st character behind the ruler or viewport edge.
  - [x] **Word End Operators (`de`, `ce`, `ye`)**:
    - [x] In `libvim_bridge.c`, add `*p == 'e'` handling to `op == 'd'` (`de`: delete to end of word inclusive).
    - [x] Add `*p == 'e'` handling to `op == 'c'` (`ce`: change to end of word inclusive, enter Insert mode).
    - [x] Add `*p == 'e'` handling to `op == 'y'` (`ye`: yank to end of word inclusive).
    - [x] Support count multipliers (e.g. `2de`, `3ce`, `2ye`) and single-step undo recovery.
    - [x] Memory safety: empty lines are strict no-ops preserving yank buffers and clean states.

- [x] **Milestone Q: Comprehensive Vim Replace Subsystem (`R`, `r`, Visual `r`, `s`, `S`, and Ex Substitutions)**
  - [x] **Full Overwrite Replace Mode (`R`)**:
    - [x] Add `VIM_MODE_REPLACE` mode (`-- REPLACE --` displayed in status bar).
    - [x] Overwrite existing characters one-by-one as typed without shifting the remainder of the line.
    - [x] Extend line length automatically when typing past line end.
    - [x] Support Backspace (`⌫`) restoring original overwritten characters during active Replace session.
    - [x] Pressing `<Esc>` exits Replace mode to Normal mode with single cohesive undo history.
  - [x] **Single Character Replacement (`r<ch>`)**:
    - [x] Replace character under cursor with typed character in Normal mode; support multibyte UTF-8 characters (`é`, `世`, `😀`).
  - [x] **Visual Replace (`v...r<ch>`, `V...r<ch>`)**:
    - [x] In visual character or visual line selection, `r<ch>` replaces all selected characters with `<ch>`.
  - [x] **Substitution Mutations (`s`, `S`)**:
    - [x] `s` (substitute character) and `S` (substitute entire line) entering Insert mode.
  - [x] **Ex Substituted Manifestations (`:%s`, `:s`, `:'<,'>s`)**:
    - [x] Line range replacements with flags `g` (global), `i` (case-insensitive), and `I` (case-sensitive).

---

## 3. Function & Schema Verification Matrix
Tracks live verification status of all capabilities across each supported document schema:

| Function Category | Capability / Keystroke | Spreadsheet (`.csv`, `.tsv`) | Markdown (`.md`) | Plain Text / Code (`.txt`, `.sh`, `.json`) |
| :--- | :--- | :---: | :---: | :---: |
| **Horizontal Motions** | `h`, `l`, `0`, `^`, `$` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Vertical Motions** | `j`, `k`, `gg`, `G` | Verified (M-U) | Verified (M-P) | Verified (M-P) |
| **Word Motions** | `w`, `b`, `e`, `ge` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Find Motions** | `f<ch>`, `t<ch>`, `;`, `,` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Counted Jumps** | `3w`, `2j`, `5G`, `10l` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Insert Transitions** | `i`, `I`, `a`, `A`, `o`, `O` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Line Deletion & Yank** | `dd`, `yy`, `p`, `P` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Word & Part Mutations** | `dw`, `de`, `cw`, `ce`, `d$`, `c$`, `d0` | Verified (M-W) | Verified (M-W) | Verified (M-W) |
| **Char Replacements** | `x`, `s`, `r<ch>`, `R`, `S`, `cc`, `J` | Verified (M-Q) | Verified (M-Q) | Verified (M-Q) |
| **Text Objects** | `di'`, `ci"`, `yi(`, `di[`, `ci<`, `ci{` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Visual Modes** | `v`, `V`, block selections | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Undo / Redo** | `u`, `Ctrl-R` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Ex Substitutions** | `:%s`, `:s`, `:'<,'>s`, flags `g`, `i`, `I` | Verified (M-Q) | Verified (M-Q) | Verified (M-Q) |
| **Line Sorting** | `:sort`, `:sort!`, `:sort u`, `:sort n` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Search Pipeline** | `/pattern<CR>`, `n`, `N`, `p` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Lifecycle & Safety** | `:w`, `ZZ`, `:q` (E37 block), `:q!` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Zoom Controls** | `Cmd+=`, `Cmd+-`, `Cmd+0` | Verified (M-P) | Verified (M-P) | Verified (M-P) |
| **Freeze Panes** | `Freeze First Row`, `Freeze Col` | Verified (M-P) | N/A (Disabled) | N/A (Disabled) |
| **Table Formatting** | Neutral gridlines, text wrap | Verified (M-P) | N/A (GFM Tables) | N/A (Monospace) |
| **Cell Caret Positioning** | Click cell -> First character offset | Verified (M-R) | N/A (Standard Caret) | N/A (Standard Caret) |
| **Copy Gestures** | Column A / Row 1 Drag-to-Copy | Verified (M-P) | N/A | N/A |
| **App Branding** | High-contrast cursor, `v.circle` | Verified (M-N) | Verified (M-N) | Verified (M-N) |

---

## 4. Completed Milestones
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
- [x] Excel-Style Spreadsheet View for CSV & TSV: Gridlines, Neutral Palette, Dynamic Sizing, Wrap, Freeze Panes, and Copy Gestures (Milestone M)

