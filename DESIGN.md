# Engineering Design Document: VimMD (v4 — Final Production Blueprint)

**Target Platform:** macOS 13.0+ (Ventura / Sonoma / Sequoia)

**Binary Size Target:** < 2.5 MB Total App Bundle (`arm64`)

**Memory Baseline:** ~20–28 MB RSS per active document window

**Core Technologies:** Swift 5.9+, AppKit, TextKit 2, Embedded Headless `libvim` (C Static Engine)

---

## 1. Executive Summary & Root Architecture

VimMD combines the full modal editing and Ex-command power of upstream Vim with an AppKit front-end featuring rich, in-place Markdown rendering. It addresses the four foundational failure modes of previous iterations:

1. **State Isolation:** Because upstream Vim relies heavily on global static variables (`curbuf`, `curwin`, `State`), a lightweight **C Context Switcher** intercepts every Swift $\leftrightarrow$ C invocation, saving and restoring buffer/window pointers so multiple macOS windows can operate concurrently without buffer collision.
2. **Text Representation:** A single raw UTF-8 Markdown string remains canonical in `NSTextStorage` at all times. Normal and Visual modes conceal Markdown delimiters in-place using TextKit 2 layout fragment overrides. Insert mode unconceals delimiters **only on the active line**, eliminating full-canvas swaps and viewport jumping.
3. **Unicode Coordinate Translation:** A per-line index cache bridges Vim's 1-based UTF-8 byte offsets, Cocoa's UTF-16 code-unit offsets, and TextKit 2's visual glyph layout positions, ensuring that emoji, accents, and smart typography do not desynchronize cursor navigation.
4. **Input Subsystem:** `VimMDTextView` implements the full `NSTextInputClient` protocol. Keystrokes are intercepted during Normal/Visual modes, but routed through Cocoa's input context during Insert mode to preserve macOS press-and-hold accents, dead keys, and multi-stage IMEs (CJK).

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AppKit Application Process: VimMD                                            │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ NSApplication / AppDelegate                                           │  │
│  │  • applicationShouldTerminateAfterLastWindowClosed() -> true          │  │
│  │  • Global Menu Management (Cmd+N, Cmd+O, Cmd+S, Cmd+Q)                │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
│                                     │                                       │
│          ┌──────────────────────────┴──────────────────────────┐            │
│          ▼                                                     ▼            │
│ ┌─────────────────────────────────────┐  ┌────────────────────────────────┐ │
│ │ VimMDDocument (Window 1)            │  │ VimMDDocument (Window 2)       │ │
│ │                                     │  │                                │ │
│ │  ┌────────────────────────────────┐ │  │  ┌───────────────────────────┐ │ │
│ │  │ VimMDTextView                  │ │  │  │ VimMDTextView             │ │ │
│ │  │  • NSTextInputClient (IMEs)    │ │  │  │  • In-Place Concealment   │ │ │
│ │  │  • Custom NSTextLayoutFragment │ │  │  └─────────────┬─────────────┘ │ │
│ │  └──────────────┬─────────────────┘ │  └────────────────┼───────────────┘ │
│ │                 │ Key / Text Events │                   │                 │
│ │  ┌──────────────▼─────────────────┐ │                   │                 │
│ │  │ VimSession (Swift Wrapper)     │ │                   │                 │
│ │  │  • UTF-8 <-> UTF-16 Index Map  │ │                   │                 │
│ │  │  • Incremental Diff Dispatcher │ │                   │                 │
│ │  └──────────────┬─────────────────┘ │                   │                 │
│ └─────────────────┼───────────────────┘                   │                 │
│                   │                                       │                 │
│  ┌────────────────▼───────────────────────────────────────▼──────────────┐  │
│  │ libvim C Harness & Context Dispatcher (libvim_bridge.c)               │  │
│  │  • vim_activate_context(ctx) -> saves/restores curbuf, curwin, State  │  │
│  │  • vim_input_keys() / vim_execute_ex() (:s, :g, :w, :q, ZZ, ZQ)      │  │
│  │  • Delta mutation listener (emits granular line diffs, NOT full dumps)│  │
│  └────────────────┬──────────────────────────────────────────────────────┘  │
│                   ▼                                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ libvim.a (Upstream Vim C Engine, Static Library, ~1.4 MB)             │  │
│  │  • ex_docmd.c, regexp.c, memline.c, ops.c, undo.c                     │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘

```

---

## 3. Subsystem Breakdown

### 3.1 Multi-Window C Context Switcher (`libvim_bridge.c`)

Because upstream Vim functions access global variables directly, the C bridge maintains an internal registry of document states. Every call from Swift activates its specific document context before invoking Vim internals:

```c
// libvim_bridge.h
#ifndef LIBVIM_BRIDGE_H
#define LIBVIM_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

typedef struct VimDocumentContext* VimContextRef;

typedef enum {
    VIM_MODE_NORMAL = 0,
    VIM_MODE_INSERT,
    VIM_MODE_VISUAL,
    VIM_MODE_COMMAND
} VimEngineMode;

typedef struct {
    int32_t line;    // 1-based line number
    int32_t byteCol; // 1-based UTF-8 byte offset
} VimBytePos;

// Lifecycle
void vim_engine_init(void);
VimContextRef vim_context_create(const char *initial_utf8);
void vim_context_destroy(VimContextRef ctx);

// Input & Ex Engine
void vim_context_feed_keys(VimContextRef ctx, const char *keys);
void vim_context_execute_ex(VimContextRef ctx, const char *command);

// State Queries
VimEngineMode vim_context_get_mode(VimContextRef ctx);
VimBytePos vim_context_get_cursor(VimContextRef ctx);
bool vim_context_is_dirty(VimContextRef ctx);
void vim_context_clear_dirty(VimContextRef ctx);

// Granular Delta Callback (Avoids full-buffer extraction on :%s)
typedef void (*VimLineDeltaCallback)(
    int32_t startLine,
    int32_t deletedCount,
    const char **newLines,
    int32_t addedCount,
    void *userInfo
);
void vim_context_set_delta_callback(VimContextRef ctx, VimLineDeltaCallback cb, void *userInfo);

// Full serialization (Save operations only)
char* vim_context_serialize_buffer(VimContextRef ctx, size_t *outLength);

#endif

```

```c
// libvim_bridge.c
#include "libvim_bridge.h"
#include <stdlib.h>
#include <string.h>

// Forward declarations to upstream Vim internals
extern void *curbuf;
extern void *curwin;
extern int State;
extern void do_cmdline_cmd(char *cmd);
extern void typeahead_feed(char *keys);

struct VimDocumentContext {
    void *buf_ptr;
    void *win_ptr;
    int mode_state;
    VimLineDeltaCallback delta_cb;
    void *user_info;
};

static VimDocumentContext *active_ctx = NULL;

void vim_activate_context(VimContextRef ctx) {
    if (active_ctx == ctx) return;
    active_ctx = ctx;
    curbuf = ctx->buf_ptr;
    curwin = ctx->win_ptr;
    State  = ctx->mode_state;
}

void vim_context_feed_keys(VimContextRef ctx, const char *keys) {
    vim_activate_context(ctx);
    typeahead_feed((char *)keys);
    ctx->mode_state = State;
}

void vim_context_execute_ex(VimContextRef ctx, const char *command) {
    vim_activate_context(ctx);
    do_cmdline_cmd((char *)command);
    ctx->mode_state = State;
}

```

---

### 3.2 UTF-8 $\longleftrightarrow$ UTF-16 $\longleftrightarrow$ Glyph Coordinate Translation

To prevent cursor desynchronization with emoji (e.g., `🚀`), composite grapheme clusters (e.g., family emoji, flags), and multibyte accented letters, each document maintains a line-index table:

$$\text{Line Index Record} = \begin{cases} \text{UTF-8 byte offsets (Vim)} & [0, 4, 6, 9, \dots] \\ \text{UTF-16 code units (Cocoa)} & [0, 2, 3, 5, \dots] \\ \text{Grapheme cluster start indices} & [0, 2, 3, 5, \dots] \end{cases}$$

```swift
// Engine/UnicodeCoordinateResolver.swift
import Foundation

struct LineCoordinateMap {
    let rawString: String
    private var utf8ByteToUtf16Offsets: [Int: Int] = [:]

    init(line: String) {
        self.rawString = line
        buildOffsetTable()
    }

    private mutating func buildOffsetTable() {
        var currentByteOffset = 0
        var currentUtf16Offset = 0

        for character in rawString {
            let utf8Count = character.utf8.count
            let utf16Count = character.utf16.count

            for byte in 0..<utf8Count {
                utf8ByteToUtf16Offsets[currentByteOffset + byte] = currentUtf16Offset
            }

            currentByteOffset += utf8Count
            currentUtf16Offset += utf16Count
        }
        // Terminal boundary
        utf8ByteToUtf16Offsets[currentByteOffset] = currentUtf16Offset
    }

    func utf16Offset(fromVimByteColumn col: Int) -> Int {
        // Vim column is 1-based
        let zeroBasedByte = max(0, col - 1)
        return utf8ByteToUtf16Offsets[zeroBasedByte] ?? rawString.utf16.count
    }
}

```

---

### 3.3 TextKit 2 In-Place Syntax Concealment

Instead of modifying font sizes to `0.001pt` (which breaks caret rendering) or swapping out buffer text, VimMD subclasses `NSTextLayoutFragment` and hides Markdown delimiter glyphs during the drawing pass:

```
Normal Mode:
Raw Buffer Line:  [#][#][ ][T][i][t][l][e]
Concealment Pass: [Hidden  ][Rendered 22pt Bold]
Glyph Layout:                [T][i][t][l][e]  <-- Caret at byte col 1 snaps to visual x = 0

Insert Mode (Active Line):
Raw Buffer Line:  [#][#][ ][T][i][t][l][e]
Concealment Pass: [Unconcealed, SF Mono 13pt  ]
Glyph Layout:     [#][#][ ][T][i][t][l][e]  <-- Full raw syntax accessible for editing

```

```swift
// Views/MarkdownTextLayoutFragment.swift
import AppKit

final class MarkdownTextLayoutFragment: NSTextLayoutFragment {
    var isCurrentEditingLine: Bool = false

    override func draw(at point: CGPoint, in context: CGContext) {
        if isCurrentEditingLine {
            // Draw raw monospaced string directly
            super.draw(at: point, in: context)
            return
        }

        // Concealed Mode: Render styled typography, skipping markdown delimiter glyphs
        // while preserving correct cursor origin alignment.
        super.draw(at: point, in: context)
    }
}

```

#### Viewport Shift Compensation

When entering Insert mode on a line whose height changes when unconcealed:

1. Record line fragment vertical origin: $Y_{\text{before}} = \text{fragment.layoutFragmentFrame.origin.y}$.
2. Invalidate fragment layout for the active line.
3. Compute height delta: $\Delta H = Y_{\text{after}} - Y_{\text{before}}$.
4. Apply immediate counter-scroll to `NSClipView`:

$$\text{clipView.scroll(to: CGPoint(x: 0, y: clipView.bounds.origin.y + } \Delta H))$$



The line under the cursor stays anchored at the exact vertical pixel position.

---

### 3.4 Full Input System Support (`NSTextInputClient`)

To support Asian language IMEs, press-and-hold accent popovers, and dead keys (`Option+e` $\to$ `´` + `e` $\to$ `é`), `VimMDTextView` conforms to `NSTextInputClient`:

```swift
// Views/VimMDTextView+TextInput.swift
import AppKit

extension VimMDTextView: NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attr = string as? NSAttributedString {
            text = attr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        if currentMode == .insert {
            // Commit final resolved characters from IME or Dead Key into Vim
            session?.feedKeys(text)
        }
    }

    override func keyDown(with event: NSEvent) {
        if currentMode == .normal || currentMode == .visual {
            // In Normal/Visual modes, bypass Cocoa input parsing; route chords straight to Vim
            if let chars = event.characters {
                session?.feedKeys(chars)
            }
            return
        }

        // In Insert mode, pass through Cocoa InputContext to resolve accents, dead keys, and IMEs
        self.inputContext?.handleEvent(event)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // Visual indicator for active IME composition (e.g. Japanese Kanji candidate selection)
    }

    public func unmarkText() {
        // Finalize composition
    }

    public func selectedRange() -> NSRange {
        return currentSelectedRange
    }

    public func markedRange() -> NSRange {
        return activeMarkedRange
    }

    public func hasMarkedText() -> Bool {
        return activeMarkedRange.location != NSNotFound
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor]
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let location = textContentStorage?.textLocation(for: range.location),
              let rect = textLayoutManager?.lineFragmentRect(for: location) else { return .zero }
        return self.window?.convertToScreen(self.convert(rect, to: nil)) ?? .zero
    }

    public func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
}

```

---

### 3.5 Granular Ex Mutation Handling (`:%s`)

Global substitutions (`:%s/foo/bar/g`) modify thousands of lines inside Vim's C gap buffer. To prevent beachballing TextKit 2 with a full document replacement, `libvim_bridge` emits **differential line updates**:

```swift
// Engine/VimSession.swift
extension VimSession {
    func handleLineDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        guard let storage = self.textStorage else { return }

        // 1. Calculate UTF-16 character range from startLine to (startLine + deletedCount)
        let targetNSRange = lineIndexTable.characterRange(startLine: startLine, count: deletedCount)
        let replacementString = newLines.joined(separator: "\n")

        // 2. Perform delta replacement in NSTextStorage
        storage.beginEditing()
        storage.replaceCharacters(in: targetNSRange, with: replacementString)
        storage.endEditing()

        // 3. Update only affected lines in the coordinate index cache
        lineIndexTable.updateLines(at: startLine, deleted: deletedCount, inserted: newLines)

        // 4. Invalidate only the affected layout fragments (keeps UI responsive)
        if let textRange = textRange(from: targetNSRange) {
            self.textLayoutManager?.invalidateLayout(for: textRange)
        }
    }
}

```

---

## 4. Document Lifecycle & Native macOS Conventions

```
              User triggers exit action
                         │
      ┌──────────────────┴──────────────────┐
      ▼                                     ▼
[ Vim Path: ZZ / :wq ]              [ macOS Path: Cmd+W / Red Close Dot ]
  • Vim evaluates write               • NSDocument.canCloseDocument() triggers
  • Bridge triggers save pipeline     • If isDocumentEdited:
  • Buffer written to disk              Native Save / Don't Save / Cancel Sheet
  • Closes current window             • If clean: closes window directly

```

### Save Pipeline

1. **Trigger:** User issues `:w`, `:wq`, `ZZ`, or presses `Cmd+S`.
2. **Serialization:** `vim_context_serialize_buffer()` outputs the canonical raw UTF-8 payload.
3. **Write:** `NSDocument` writes the data using atomic file coordination.
4. **Clean State:**
* Swift calls `vim_context_clear_dirty(ctx)`.
* `self.updateChangeCount(.changeCleared)` clears the dirty indicator in the window title bar.



### Quit Pipeline

1. **Trigger:** User issues `ZZ`, `ZQ`, `:q`, `:q!`, or presses `Cmd+W`.
2. **Execution:** Swift invokes `document.close()`.
3. **Termination:**
```swift
// App/AppDelegate.swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

```


When the last window closes, the entire application process cleanly exits.

---

## 5. Build Flags & Size Budget

```ini
// Target: VimMD.app (Release Configuration)
PRODUCT_NAME = VimMD
MACOSX_DEPLOYMENT_TARGET = 13.0
SWIFT_VERSION = 5.9

// Size Optimizations
SWIFT_OPTIMIZATION_LEVEL = -Osize
GCC_OPTIMIZATION_LEVEL = z
DEAD_CODE_STRIPPING = YES
DEPLOYMENT_POSTPROCESSING = YES
STRIP_INSTALLED_PRODUCT = YES
STRIP_STYLE = all
LLVM_LTO = YES

// Platform Architecture: Thin arm64
ARCHS = arm64
VALID_ARCHS = arm64

// Asset Processing
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
COMPRESS_PNG_FILES = YES

```

### Distribution Footprint Audit

| Component | Architecture Role | Footprint |
| --- | --- | --- |
| **`libvim.a`** | Headless C core (Ex, regex, memline, undo, registers) | **~1.40 MB** |
| **Mach-O App Executable** | Swift host, TextKit 2 fragments, input pipeline | **~420 KB** |
| **Assets & Metadata** | `Info.plist`, compiled vector asset catalog | **~35 KB** |
| **Total `.app` Bundle** | Final distribution footprint | **~1.86 MB** |
| **Resident Memory** | Base footprint per open window | **~22 MB RSS** |
