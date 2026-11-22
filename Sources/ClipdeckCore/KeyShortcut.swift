import AppKit
import Carbon.HIToolbox

public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    public init(eventFlags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, ShortcutModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self = pairs.filter { eventFlags.contains($0.0) }.reduce(into: ShortcutModifiers()) { $0.formUnion($1.1) }
    }
}

public struct KeyShortcut: Hashable, Sendable {
    public static let standard = KeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control, .shift, .command])

    private static let carbonFlags: [(ShortcutModifiers, Int)] = [
        (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
    ]
    private static let symbols: [(ShortcutModifiers, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    public let keyCode: UInt32
    public let modifiers: ShortcutModifiers

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        let modifiers = Self.carbonFlags
            .filter { carbonModifiers & UInt32($0.1) != 0 }
            .reduce(into: ShortcutModifiers()) { $0.formUnion($1.0) }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    public var carbonModifiers: UInt32 {
        Self.carbonFlags.filter { modifiers.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
    }

    // A bare ⌘ shortcut would take over an app command such as ⌘C in every app.
    public var isValid: Bool {
        KeyboardLayout.isFunctionKey(keyCode)
            || !modifiers.isDisjoint(with: [.control, .option])
            || modifiers.isSuperset(of: [.command, .shift])
    }

    @MainActor
    public var displayString: String {
        display(keyName: KeyboardLayout.name(for: keyCode))
    }

    public func display(keyName: String) -> String {
        Self.symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }
}
