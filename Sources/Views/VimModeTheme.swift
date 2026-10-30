import AppKit
import Engine
import CBridge

/// Morphology of the cursor representing the current editing state.
public enum CursorMorphology: Equatable {
    /// Normal mode: Solid full-cell block covering the current glyph.
    case block
    /// Insert mode: Thin vertical I-beam (1.5–2pt bar) placed between characters.
    case verticalBar(width: CGFloat)
    /// Replace mode: Horizontal underline at the base of the character.
    case underline(height: CGFloat)
    /// Replace mode alternative: Half-height block at the base of the character.
    case halfBlock

    public static let verticalBar = CursorMorphology.verticalBar(width: 2.0)
    public static let underline = CursorMorphology.underline(height: 2.5)
}

/// Cohesive mode theme palette and geometry calculator for status display and cursor rendering.
public struct VimModeTheme {
    /// Slate grey for Normal mode (-- NORMAL --): calm, focused, and non-glaring.
    public static let normalColor = NSColor(calibratedRed: 0.50, green: 0.53, blue: 0.58, alpha: 1.0)

    /// Gentle, cohesive blue for Insert mode (-- INSERT --): clear, calm visual cue for text insertion.
    public static let insertColor = NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.88, alpha: 1.0)

    /// Harmonious royal purple / soft magenta for Visual mode (-- VISUAL --): distinctive selection state.
    public static let visualColor = NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.86, alpha: 1.0)

    /// Warm safety amber / soft orange-red for Command mode (:): focused indication of command line input.
    public static let commandColor = NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.18, alpha: 1.0)

    /// Soft teal accent for Replace mode (-- REPLACE --): distinct reminder that typing overwrites characters.
    public static let replaceColor = NSColor(calibratedRed: 0.12, green: 0.68, blue: 0.65, alpha: 1.0)

    /// Returns the coordinated theme color for the specified Vim mode.
    public static func color(for mode: VimEngineMode) -> NSColor {
        switch mode {
        case VIM_MODE_NORMAL:
            return normalColor
        case VIM_MODE_INSERT:
            return insertColor
        case VIM_MODE_VISUAL:
            return visualColor
        case VIM_MODE_COMMAND:
            return commandColor
        case VIM_MODE_REPLACE:
            return replaceColor
        default:
            return normalColor
        }
    }

    /// Returns the cursor morphology matching the specified Vim mode.
    public static func cursorMorphology(for mode: VimEngineMode) -> CursorMorphology {
        switch mode {
        case VIM_MODE_NORMAL:
            return .block
        case VIM_MODE_INSERT:
            return .verticalBar
        case VIM_MODE_VISUAL:
            return .block
        case VIM_MODE_REPLACE:
            return .underline
        case VIM_MODE_COMMAND:
            return .verticalBar
        default:
            return .block
        }
    }

    /// Returns the standard status bar mode label text for the specified mode.
    public static func statusLabelText(for mode: VimEngineMode) -> String {
        switch mode {
        case VIM_MODE_NORMAL:
            return "-- NORMAL --"
        case VIM_MODE_INSERT:
            return "-- INSERT --"
        case VIM_MODE_VISUAL:
            return "-- VISUAL --"
        case VIM_MODE_REPLACE:
            return "-- REPLACE --"
        case VIM_MODE_COMMAND:
            return ""
        default:
            return "-- \(mode) --"
        }
    }

    /// Calculates the precise cursor rect based on morphology, proposed insertion point rect, and cell width.
    public static func calculateCursorRect(for morphology: CursorMorphology, proposedRect: NSRect, cellWidth: CGFloat) -> NSRect {
        let width = cellWidth > 0 ? cellWidth : proposedRect.width
        let baseRect = NSRect(x: proposedRect.origin.x, y: proposedRect.origin.y, width: width, height: proposedRect.height)

        switch morphology {
        case .block:
            return baseRect
        case .verticalBar(let barWidth):
            let clampedWidth = max(1.5, min(2.5, barWidth))
            return NSRect(x: baseRect.origin.x, y: baseRect.origin.y, width: clampedWidth, height: baseRect.height)
        case .underline(let height):
            let clampedHeight = max(1.5, min(baseRect.height, height))
            return NSRect(x: baseRect.origin.x, y: baseRect.maxY - clampedHeight, width: baseRect.width, height: clampedHeight)
        case .halfBlock:
            let halfHeight = floor(baseRect.height / 2.0)
            return NSRect(x: baseRect.origin.x, y: baseRect.maxY - halfHeight, width: baseRect.width, height: halfHeight)
        }
    }
}
