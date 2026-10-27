import AppKit

final class VimMDDocument: NSDocument {
    override class var autosavesInPlace: Bool {
        return true
    }
}
