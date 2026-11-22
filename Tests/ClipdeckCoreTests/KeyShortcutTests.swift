import AppKit
import Testing
@testable import ClipdeckCore

@Suite("KeyShortcut")
struct KeyShortcutTests {
    @Test("should default to control shift command V")
    func standard() {
        #expect(KeyShortcut.standard == KeyShortcut(keyCode: 9, modifiers: [.control, .shift, .command]))
    }

    @Test("should convert modifiers to and from Carbon values")
    func carbon() {
        let shortcut = KeyShortcut(keyCode: 9, modifiers: [.control, .option, .shift, .command])
        #expect(shortcut.carbonModifiers == 0x100 | 0x200 | 0x800 | 0x1000)
        #expect(KeyShortcut(keyCode: 9, carbonModifiers: shortcut.carbonModifiers) == shortcut)
        #expect(KeyShortcut(keyCode: 9, carbonModifiers: 0x100 | 0x200 | 0x1000).modifiers == [.control, .shift, .command])
    }

    @Test("should read modifiers from AppKit key flags and ignore caps lock")
    func eventFlags() {
        let flags: NSEvent.ModifierFlags = [.control, .command, .shift, .capsLock, .function]
        #expect(ShortcutModifiers(eventFlags: flags) == [.control, .shift, .command])
        #expect(ShortcutModifiers(eventFlags: [.option]) == [.option])
    }

    @Test("should show modifiers in the standard macOS order")
    @MainActor
    func display() {
        #expect(KeyShortcut(keyCode: 9, modifiers: [.command, .shift, .control]).display(keyName: "V") == "⌃⇧⌘V")
        #expect(KeyShortcut(keyCode: 9, modifiers: [.option, .command]).display(keyName: "V") == "⌥⌘V")
        #expect(KeyShortcut(keyCode: 9, modifiers: [.control, .shift, .command]).displayString == "⌃⇧⌘V")
    }

    @Test("should need command, control or option unless it is a function key")
    func validity() {
        #expect(KeyShortcut(keyCode: 9, modifiers: [.shift, .command]).isValid)
        #expect(KeyShortcut(keyCode: 9, modifiers: [.control]).isValid)
        #expect(!KeyShortcut(keyCode: 8, modifiers: [.command]).isValid)
        #expect(KeyShortcut(keyCode: 96, modifiers: [.command]).isValid)
        #expect(!KeyShortcut(keyCode: 9, modifiers: [.shift]).isValid)
        #expect(!KeyShortcut(keyCode: 9, modifiers: []).isValid)
        #expect(KeyShortcut(keyCode: 96, modifiers: []).isValid)
    }
}

@Suite("KeyboardLayout")
@MainActor
struct KeyboardLayoutTests {
    @Test("should name special keys", arguments: [
        (UInt32(36), "↩"), (49, "Space"), (51, "⌫"), (53, "⎋"), (48, "⇥"), (96, "F5"), (111, "F12"), (126, "↑"),
    ])
    func special(keyCode: UInt32, name: String) {
        #expect(KeyboardLayout.name(for: keyCode) == name)
    }

    @Test("should name letter keys from the Latin keyboard layout")
    func letters() {
        #expect(KeyboardLayout.name(for: 9) == "V")
        #expect(KeyboardLayout.name(for: 0) == "A")
    }

    @Test("should find the key code that types a character")
    func keyCode() {
        #expect(KeyboardLayout.keyCode(for: "v") == 9)
        #expect(KeyboardLayout.keyCode(for: "€") == nil)
    }
}

@Suite("Preferences")
struct PreferencesTests {
    private func withPreferences(_ body: (Preferences, UserDefaults) -> Void) {
        let suite = "clipdeck-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(Preferences(defaults: defaults), defaults)
    }

    @Test("should return sensible defaults on first launch")
    func defaults() {
        withPreferences { preferences, _ in
        #expect(preferences.shortcut == .standard)
        #expect(preferences.retention == .oneMonth)
        #expect(preferences.pasteDirectly)
        #expect(!preferences.isPaused)
        #expect(!preferences.hasLaunchedBefore)
        #expect(preferences.ignoredBundleIDs == Preferences.defaultIgnoredBundleIDs)
        }
    }

    @Test("should save the shortcut as plain integers")
    func saveShortcut() {
        withPreferences { preferences, defaults in
        preferences.shortcut = KeyShortcut(keyCode: 9, modifiers: [.control, .shift, .command])
        #expect(defaults.integer(forKey: "hotKeyCode") == 9)
        #expect(defaults.integer(forKey: "hotKeyModifiers") == 0x1000 | 0x200 | 0x100)
        #expect(preferences.shortcut == KeyShortcut(keyCode: 9, modifiers: [.control, .shift, .command]))
        }
    }

    @Test("should fall back to the default shortcut when the saved one is invalid")
    func invalidShortcut() {
        withPreferences { preferences, defaults in
        defaults.set(9, forKey: "hotKeyCode")
        defaults.set(0, forKey: "hotKeyModifiers")
        #expect(preferences.shortcut == .standard)
        }
    }

    @Test("should save every other setting")
    func saveAll() {
        withPreferences { preferences, defaults in
        preferences.retention = .forever
        preferences.pasteDirectly = false
        preferences.isPaused = true
        preferences.hasLaunchedBefore = true
        preferences.ignoredBundleIDs = ["a.b"]
        let reread = Preferences(defaults: defaults)
        #expect(reread.retention == .forever)
        #expect(!reread.pasteDirectly)
        #expect(reread.isPaused)
        #expect(reread.hasLaunchedBefore)
        #expect(reread.ignoredBundleIDs == ["a.b"])
        }
    }

    @Test("should remember where the panel was moved and forget it on reset")
    func panelPosition() {
        withPreferences { preferences, defaults in
        #expect(preferences.panelTopLeft == nil)
        preferences.panelTopLeft = CGPoint(x: 120, y: 800)
        #expect(Preferences(defaults: defaults).panelTopLeft == CGPoint(x: 120, y: 800))
        preferences.panelTopLeft = nil
        #expect(preferences.panelTopLeft == nil)
        }
    }

    @Test("should start with the system look and full glass")
    func appearanceDefaults() {
        withPreferences { preferences, _ in
        #expect(preferences.appearance == .system)
        #expect(preferences.theme == .system)
        #expect(preferences.glass == 1)
        }
    }

    @Test("should remember the appearance, accent and glass level")
    func appearanceRoundTrip() {
        withPreferences { preferences, defaults in
        preferences.appearance = .dark
        preferences.theme = .graphite
        preferences.glass = 0.4
        let reread = Preferences(defaults: defaults)
        #expect(reread.appearance == .dark)
        #expect(reread.theme == .graphite)
        #expect(reread.glass == 0.4)
        }
    }

    @Test("should keep the glass level between solid and clear")
    func glassClamped() {
        withPreferences { preferences, defaults in
        preferences.glass = 3
        #expect(preferences.glass == 1)
        defaults.set(-2.0, forKey: "glass")
        #expect(preferences.glass == 0)
        }
    }

    @Test("should fall back to the system look when the saved one is unknown")
    func unknownAppearance() {
        withPreferences { preferences, defaults in
        defaults.set("neon", forKey: "appearance")
        defaults.set("neon", forKey: "theme")
        #expect(preferences.appearance == .system)
        #expect(preferences.theme == .system)
        }
    }

    @Test("should fall back to one month when the saved retention is unknown")
    func unknownRetention() {
        withPreferences { preferences, defaults in
        defaults.set(12345, forKey: "retentionDays")
        #expect(preferences.retention == .oneMonth)
        }
    }
}
