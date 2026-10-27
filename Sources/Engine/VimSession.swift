import Foundation
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

    session.applyLineDelta(startLine: Int(startLine), deletedCount: Int(deletedCount), newLines: lines)
    session.onLineDelta?(startLine, deletedCount, lines)
}

public final class VimSession {
    private var context: VimContextRef?

    /// Closure callback invoked when granular line mutations are emitted by the Vim engine.
    public var onLineDelta: ((Int32, Int32, [String]) -> Void)?

    /// Internal line coordinate index table synchronized with document mutations.
    public private(set) var lineIndexTable: LineIndexTable

    internal func applyLineDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        lineIndexTable.updateLines(at: startLine, deleted: deletedCount, inserted: newLines)
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
        }
    }

    deinit {
        if let ctx = context {
            vim_context_set_delta_callback(ctx, nil, nil)
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

    public var shouldQuit: Bool {
        guard let ctx = context else { return false }
        return vim_context_should_quit(ctx)
    }

    public var isDirty: Bool {
        guard let ctx = context else { return false }
        return vim_context_is_dirty(ctx)
    }

    public func feedKeys(_ keys: String) {
        guard let ctx = context else { return }
        keys.withCString { cKeys in
            vim_context_feed_keys(ctx, cKeys)
        }
    }

    public func executeEx(_ command: String) {
        guard let ctx = context else { return }
        command.withCString { cCmd in
            vim_context_execute_ex(ctx, cCmd)
        }
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
