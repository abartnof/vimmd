# VimMD

> A native macOS hybrid editor uniting true Vim modal editing with rich typography and spreadsheet navigation.

`VimMD` combines headless modal engine semantics with native AppKit text layout. It delivers instantaneous, zero-latency Vim editing without terminal emulation or Electron overhead.

---

## What It Is

`VimMD` adapts dynamically to document formats while preserving a single canonical raw buffer:

- **Markdown (`.md`)**: In-place syntax concealment for headings, bold, italics, strikethrough, code blocks, and task lists. Inactive lines display rendered typography while the active cursor line seamlessly expands to raw Markdown syntax for editing.
- **Spreadsheets (`.csv`, `.tsv`)**: Native Excel-style gridlines, full RFC 4180 multiline quoted record parsing, per-cell word-wrapping, interactive column dragging, and frozen header/row panes.
- **Plain Text & Code (`.txt`, `.sh`, `.json`, `.py`, `.swift`)**: Distraction-free monospace editing with complete Vim movement and Ex-command fidelity.

---

## How to Use It

### Modal Editing
Seamlessly switch between standard Vim modes:
- **Normal Mode** (`Esc`): Navigate using `h`, `j`, `k`, `l`, word jumps (`w`, `b`, `e`), paragraph navigation, and operator text objects (`ci"`, `da(`, etc.).
- **Insert Mode** (`i`, `a`, `o`, `I`, `A`): Full macOS text input integration (`NSTextInputClient`), including press-and-hold accents and multi-stage IMEs.
- **Visual & Visual-Line Modes** (`v`, `V`): Characterwise and linewise selection ranges.
- **Replace Mode** (`R`): Overwrite text character-by-character.
- **Command-Line Mode** (`:`): Ex commands including `:w`, `:q`, `:%s/find/replace/g`, and `:sort`.

### Visual Badges & UI
- **Synchronized Modal Badges**: Visual indicators (`NORMAL`, `INSERT`, `VISUAL`, `REPLACE`) dynamically update across the status bar and the row-number gutter.
- **Viewport Zoom**: Smooth zooming via `⌘+`, `⌘-`, `⌘0`, or trackpad pinch-to-zoom. Features proportional accessibility scaling across all rulers, gutters, and badges.
- **Custom Delimiters**: Adjust tabular delimiter styling via `View` → `Delimiter Color…`.

---

## Quick Start & Build

### Requirements
- macOS 13.0+ (Ventura, Sonoma, Sequoia)
- Xcode Command Line Tools (`swiftc`, `clang`)

### Build
Compile the native macOS application bundle:
```bash
make app
```
*Produces a native, highly optimized bundle at `build/VimMD.app`.*

### Test
Run the comprehensive 100% automated test suite:
```bash
./scripts/test.sh
```

---

## Acknowledgments & Citations

- **Bram Moolenaar & the Vim Community**: Grateful acknowledgment for creating Vim and establishing the timeless modal editing paradigms that power this application.
- **Apple Swift & AppKit**: Built natively on Swift and macOS AppKit / TextKit 2 for high-performance typographic rendering.
- **CommonMark**: Reference standard for Markdown parsing and delimiter concealment rules.
- **RFC 4180**: Standard specification governing robust CSV parsing, escapes, and multiline records.

---

## License

This project is licensed under the [MIT License](LICENSE).
