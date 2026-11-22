import CoreGraphics
import Foundation

public final class Preferences {
    public static let defaultIgnoredBundleIDs = [
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "org.keepassxc.keepassxc",
    ]

    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let retentionDays = "retentionDays"
        static let pasteDirectly = "pasteDirectly"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let isPaused = "isPaused"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let panelX = "panelX"
        static let panelTop = "panelTop"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var shortcut: KeyShortcut {
        get {
            guard defaults.object(forKey: Key.hotKeyCode) != nil else { return .standard }
            let stored = KeyShortcut(
                keyCode: UInt32(clamping: defaults.integer(forKey: Key.hotKeyCode)),
                carbonModifiers: UInt32(clamping: defaults.integer(forKey: Key.hotKeyModifiers))
            )
            return stored.isValid ? stored : .standard
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotKeyModifiers)
        }
    }

    public var retention: RetentionOption {
        get {
            guard defaults.object(forKey: Key.retentionDays) != nil else { return .oneMonth }
            return RetentionOption(rawValue: defaults.integer(forKey: Key.retentionDays)) ?? .oneMonth
        }
        set { defaults.set(newValue.rawValue, forKey: Key.retentionDays) }
    }

    public var pasteDirectly: Bool {
        get { defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pasteDirectly) }
    }

    public var ignoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? Self.defaultIgnoredBundleIDs }
        set { defaults.set(newValue, forKey: Key.ignoredBundleIDs) }
    }

    public var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    public var panelTopLeft: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Key.panelX) as? Double,
                  let top = defaults.object(forKey: Key.panelTop) as? Double else { return nil }
            return CGPoint(x: x, y: top)
        }
        set {
            if let point = newValue {
                defaults.set(Double(point.x), forKey: Key.panelX)
                defaults.set(Double(point.y), forKey: Key.panelTop)
            } else {
                defaults.removeObject(forKey: Key.panelX)
                defaults.removeObject(forKey: Key.panelTop)
            }
        }
    }

    public var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }
}
