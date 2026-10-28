import Foundation
import AppKit
import CBridge

private func vimDeltaTrampoline(
    startLine: Int32,
    deletedCount: Int32,
    newLinesPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?,
    addedCount: Int32,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let session = Unmanaged<VimSession>.fromOpaque(userInfo).takeUnretainedValue()

    var lines: [String] = []
    if let newLinesPtr = newLinesPtr, addedCount > 0 {
        lines.reserveCapacity(Int(addedCount))
        for i in 0..<Int(addedCount) {
            if let cStr = newLinesPtr[i] {
                lines.append(String(cString: cStr))
            }
        }
    }

    session.handleLineDelta(startLine: Int(startLine), deletedCount: Int(deletedCount), newLines: lines)
}

private func vimYankTrampoline(
    textPtr: UnsafePointer<CChar>?,
    linewise: Bool,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo, let textPtr = textPtr else { return }
    let session = Unmanaged<VimSession>.fromOpaque(userInfo).takeUnretainedValue()
    let text = String(cString: textPtr)
    session.handleYank(text: text, linewise: linewise)
}

public final class VimSession {
    private var context: VimContextRef?

    /// Closure callback invoked when granular line mutations are emitted by the Vim engine.
    public var onLineDelta: ((Int32, Int32, [String]) -> Void)?

    /// Closure callback invoked when text is yanked or cut by the Vim engine.
    public var onYank: ((String, Bool) -> Void)?

    /// Internal line coordinate index table synchronized with document mutations.
    public private(set) var lineIndexTable: LineIndexTable

    /// Callback providing pre-calculated characterRange for TextKit 2 synchronization per DESIGN.md §3.5
    public var onLineDeltaWithRange: ((Int, Int, [String], NSRange) -> Void)?

    /// Callback invoked when a system action (:w, :q, :wq, etc.) is emitted by the Vim engine.
    public var onSystemAction: ((VimSystemAction) -> Void)?

    /// Callback invoked when the Vim mode changes (NORMAL, INSERT, VISUAL, COMMAND).
    public var onModeChanged: ((VimEngineMode) -> Void)?

    /// Callback invoked when session status or error states may have changed.
    public var onStatusChanged: (() -> Void)?

    public var yankBuffer: (text: String, linewise: Bool)? {
        guard let ctx = context else { return nil }
        var linewise: Bool = false
        guard let cStr = vim_context_get_yank_buffer(ctx, &linewise) else { return nil }
        return (String(cString: cStr), linewise)
    }

    public func setYankBuffer(text: String, linewise: Bool) {
        guard let ctx = context else { return }
        text.withCString { cStr in
            vim_context_set_yank_buffer(ctx, cStr, linewise)
        }
    }

    internal func handleYank(text: String, linewise: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        onYank?(text, linewise)
    }

    internal func handleLineDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        var targetRange = lineIndexTable.characterRange(startLine: startLine, count: deletedCount)
        if newLines.isEmpty && deletedCount > 0 {
            let startIdx = max(0, startLine - 1)
            let endIdx = min(lineIndexTable.lineCount - 1, startIdx + deletedCount - 1)
            if endIdx + 1 < lineIndexTable.lineCount {
                targetRange.length += 1
            } else if startIdx > 0 {
                targetRange.location -= 1
                targetRange.length += 1
            }
        }
        lineIndexTable.updateLines(at: startLine, deleted: deletedCount, inserted: newLines)
        onLineDeltaWithRange?(startLine, deletedCount, newLines, targetRange)
        onLineDelta?(Int32(startLine), Int32(deletedCount), newLines)
    }

    public init(initialText: String) {
        self.lineIndexTable = LineIndexTable(documentText: initialText)
        self.context = initialText.withCString { cStr in
            vim_context_create(cStr)
        }
        if let ctx = context {
            vim_context_set_delta_callback(
                ctx,
                vimDeltaTrampoline,
                Unmanaged.passUnretained(self).toOpaque()
            )
            vim_context_set_yank_callback(
                ctx,
                vimYankTrampoline,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    deinit {
        if let ctx = context {
            vim_context_set_delta_callback(ctx, nil, nil)
            vim_context_set_yank_callback(ctx, nil, nil)
            vim_context_destroy(ctx)
            context = nil
        }
    }

    public var isValid: Bool {
        return context != nil
    }

    public var mode: VimEngineMode {
        guard let ctx = context else { return VIM_MODE_NORMAL }
        return vim_context_get_mode(ctx)
    }

    public var modeString: String {
        switch mode {
        case VIM_MODE_NORMAL: return "NORMAL"
        case VIM_MODE_INSERT: return "INSERT"
        case VIM_MODE_VISUAL: return "VISUAL"
        case VIM_MODE_COMMAND: return "COMMAND"
        default: return "NORMAL"
        }
    }

    public func setCursor(line: Int, byteCol: Int) {
        guard let ctx = context else { return }
        vim_context_set_cursor(ctx, Int32(line), Int32(byteCol))
    }

    public var cursor: VimBytePos {
        guard let ctx = context else { return VimBytePos(line: 1, byteCol: 1) }
        return vim_context_get_cursor(ctx)
    }

    public var cursorPosition: (line: Int, byteCol: Int) {
        let pos = cursor
        return (Int(pos.line), Int(pos.byteCol))
    }

    public var cursorUtf16Offset: Int {
        let pos = cursorPosition
        return lineIndexTable.documentUtf16Offset(line: pos.line, vimByteCol: pos.byteCol)
    }

    public var visualAnchor: VimBytePos {
        guard let ctx = context else { return VimBytePos(line: 1, byteCol: 1) }
        return vim_context_get_visual_anchor(ctx)
    }

    public var visualAnchorPosition: (line: Int, byteCol: Int) {
        let a = visualAnchor
        return (Int(a.line), Int(a.byteCol))
    }

    public var isVisualLinewise: Bool {
        guard let ctx = context else { return false }
        return vim_context_is_visual_linewise(ctx)
    }

    public var visualSelectionRange: NSRange? {
        guard mode == VIM_MODE_VISUAL else { return nil }
        let aPos = visualAnchorPosition
        let cPos = cursorPosition

        if isVisualLinewise {
            let startLine = min(aPos.line, cPos.line)
            let endLine = max(aPos.line, cPos.line)
            return lineIndexTable.characterRange(startLine: startLine, count: endLine - startLine + 1)
        }

        let aOffset = lineIndexTable.documentUtf16Offset(line: aPos.line, vimByteCol: aPos.byteCol)
        let cOffset = lineIndexTable.documentUtf16Offset(line: cPos.line, vimByteCol: cPos.byteCol)

        let docLength = lineIndexTable.totalUtf16Length
        if aPos.line == cPos.line && aPos.byteCol > cPos.byteCol {
            // Empty inner text object (e.g. "")
            let clampedLoc = min(max(0, aOffset), docLength)
            return NSRange(location: clampedLoc, length: 0)
        }

        let start = min(aOffset, cOffset)
        let end = max(aOffset, cOffset)
        let length = max(0, end - start + 1)
        let clampedStart = min(max(0, start), docLength)
        let clampedLength = min(length, max(0, docLength - clampedStart))
        return NSRange(location: clampedStart, length: clampedLength)
    }

    public var lastSearchPattern: String? {
        guard let ctx = context else { return nil }
        guard let cStr = vim_context_get_last_search(ctx) else { return nil }
        let s = String(cString: cStr)
        return s.isEmpty ? nil : s
    }

    public func searchForward(_ pattern: String) {
        feedKeys("/" + pattern + "\r")
    }

    public func searchNext() {
        feedKeys("n")
    }

    public func searchPrevious() {
        feedKeys("N")
    }

    public var shouldQuit: Bool {
        guard let ctx = context else { return false }
        return vim_context_should_quit(ctx)
    }

    public var isDirty: Bool {
        guard let ctx = context else { return false }
        return vim_context_is_dirty(ctx)
    }

    public var pendingAction: VimSystemAction {
        guard let ctx = context else { return VIM_ACTION_NONE }
        return vim_context_get_pending_action(ctx)
    }

    public func clearPendingAction() {
        guard let ctx = context else { return }
        vim_context_clear_pending_action(ctx)
    }

    public var lastError: String? {
        guard let ctx = context else { return nil }
        guard let cStr = vim_context_get_last_error(ctx) else { return nil }
        let str = String(cString: cStr)
        return str.isEmpty ? nil : str
    }

    private func checkAndDispatchPendingAction() {
        let action = pendingAction
        if action != VIM_ACTION_NONE {
            onSystemAction?(action)
        }
    }

    private func syncPasteboardIfPasting(keys: String) {
        guard mode == VIM_MODE_NORMAL || mode == VIM_MODE_VISUAL else { return }
        if keys.contains("p") || keys.contains("P") {
            if let pbText = NSPasteboard.general.string(forType: .string) {
                let currentYank = yankBuffer?.text
                if currentYank != pbText {
                    let isLinewise = pbText.hasSuffix("\n")
                    setYankBuffer(text: pbText, linewise: isLinewise)
                }
            }
        }
    }

    public func feedKeys(_ keys: String) {
        guard let ctx = context else { return }
        syncPasteboardIfPasting(keys: keys)
        let oldMode = mode
        keys.withCString { cKeys in
            vim_context_feed_keys(ctx, cKeys)
        }
        let newMode = mode
        if newMode != oldMode {
            onModeChanged?(newMode)
        }
        checkAndDispatchPendingAction()
        onStatusChanged?()
    }

    public func executeEx(_ command: String) {
        guard let ctx = context else { return }
        let oldMode = mode
        command.withCString { cCmd in
            vim_context_execute_ex(ctx, cCmd)
        }
        let newMode = mode
        if newMode != oldMode {
            onModeChanged?(newMode)
        }
        checkAndDispatchPendingAction()
        onStatusChanged?()
    }

    public func clearDirty() {
        guard let ctx = context else { return }
        vim_context_clear_dirty(ctx)
    }

    public func serializeBuffer() -> String {
        guard let ctx = context else { return "" }
        var length: Int = 0
        guard let rawPtr = vim_context_serialize_buffer(ctx, &length) else {
            return ""
        }
        defer { free(rawPtr) }
        return String(cString: rawPtr)
    }

    public var canUndo: Bool {
        guard let ctx = context else { return false }
        return vim_context_can_undo(ctx)
    }

    public var canRedo: Bool {
        guard let ctx = context else { return false }
        return vim_context_can_redo(ctx)
    }

    public func undo() {
        if mode != VIM_MODE_NORMAL {
            feedKeys("\u{1b}")
        }
        feedKeys("u")
    }

    public func redo() {
        if mode != VIM_MODE_NORMAL {
            feedKeys("\u{1b}")
        }
        feedKeys("\u{12}")
    }

    public func triggerLineDelta(startLine: Int32, deletedCount: Int32, newLines: [String]) {
        guard let ctx = context else { return }
        // Convert array of strings into null-terminated C strings array
        let utf8Buffers: [ContiguousArray<CChar>] = newLines.map { $0.utf8CString }
        var pointers: [UnsafePointer<CChar>?] = utf8Buffers.map { buffer in
            buffer.withUnsafeBufferPointer { $0.baseAddress }
        }
        pointers.withUnsafeMutableBufferPointer { bufferPtr in
            vim_context_dispatch_delta(
                ctx,
                startLine,
                deletedCount,
                bufferPtr.baseAddress,
                Int32(newLines.count)
            )
        }
    }
}
