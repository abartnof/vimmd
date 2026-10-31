import AppKit

/// Central manager for non-printing and syntax delimiter color configuration, persistence, and change broadcasting.
public final class DelimiterColorManager {
    public static let shared = DelimiterColorManager()
    public static let userDefaultsKey = "VimMDDelimiterColorKey"
    public static let didChangeNotification = Notification.Name("VimMDDelimiterColorDidChangeNotification")

    public static var defaultColor: NSColor {
        return NSColor.tertiaryLabelColor
    }

    private let userDefaults: UserDefaults
    private var cachedColor: NSColor?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The current delimiter color, persisted securely to UserDefaults with in-memory caching.
    public var delimiterColor: NSColor {
        get {
            if let cached = cachedColor {
                return cached
            }
            guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else {
                cachedColor = Self.defaultColor
                return Self.defaultColor
            }
            do {
                if let color = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                    cachedColor = color
                    return color
                }
            } catch {
                // If persisted data is corrupt or incompatible, fall back safely to default
            }
            cachedColor = Self.defaultColor
            return Self.defaultColor
        }
        set {
            cachedColor = newValue
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
                userDefaults.set(data, forKey: Self.userDefaultsKey)
            } catch {
                // Ignore archive failures
            }
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: newValue
            )
        }
    }

    /// Resets delimiter color preference to system default (NSColor.tertiaryLabelColor).
    public func resetToDefault() {
        cachedColor = nil
        userDefaults.removeObject(forKey: Self.userDefaultsKey)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: Self.defaultColor
        )
    }

    /// Clears the in-memory cached color to force reloading from persistent store.
    public func invalidateCache() {
        cachedColor = nil
    }
}
