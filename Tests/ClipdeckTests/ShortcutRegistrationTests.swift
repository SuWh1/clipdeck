import Foundation
import ClipdeckCore
import Testing
@testable import Clipdeck

@Suite("Shortcut registration")
@MainActor
struct ShortcutRegistrationTests {
    private let first = KeyShortcut(keyCode: 105, modifiers: [.control, .option, .shift, .command])
    private let second = KeyShortcut(keyCode: 107, modifiers: [.control, .option, .shift, .command])

    @Test("should keep the working shortcut when the new one is already taken")
    func keepsOldOnConflict() {
        let owner = HotKeyCenter()
        let center = HotKeyCenter()
        defer {
            owner.unregister()
            center.unregister()
        }
        #expect(owner.register(second))
        #expect(center.register(first))
        #expect(!center.register(second))
        #expect(center.registered == first)
        #expect(!HotKeyCenter().register(first))
    }

    @Test("should accept registering the same shortcut twice")
    func sameShortcut() {
        let center = HotKeyCenter()
        defer { center.unregister() }
        #expect(center.register(first))
        #expect(center.register(first))
    }
}

@Suite("Settings shortcut")
@MainActor
struct SettingsShortcutTests {
    private let wanted = KeyShortcut(keyCode: 11, modifiers: [.control, .command])

    private func withSettings(_ body: (SettingsModel, Preferences) -> Void) {
        let suite = "clipdeck-app-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        body(SettingsModel(preferences: preferences), preferences)
    }

    @Test("should save a new shortcut once it is registered")
    func savesOnSuccess() {
        withSettings { settings, preferences in
            settings.registerShortcut = { _ in true }
            settings.applyShortcut(wanted)
            #expect(settings.shortcut == wanted)
            #expect(preferences.shortcut == wanted)
            #expect(settings.shortcutError == nil)
        }
    }

    @Test("should keep the old shortcut and explain when the new one cannot be registered")
    func keepsOldOnFailure() {
        withSettings { settings, preferences in
            settings.registerShortcut = { _ in false }
            settings.applyShortcut(wanted)
            #expect(settings.shortcut == .standard)
            #expect(preferences.shortcut == .standard)
            #expect(settings.shortcutError?.isEmpty == false)
        }
    }
}
