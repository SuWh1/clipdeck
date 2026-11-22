import AppKit
import ClipdeckCore

@MainActor
final class StatusItemController: NSObject {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var currentShortcut: (() -> KeyShortcut)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isPaused = false

    override init() {
        super.init()
        guard let button = item.button else { return }
        button.image = Self.makeIcon()
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Clipdeck"
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        item.button?.appearsDisabled = paused
        item.button?.toolTip = paused ? "Clipdeck: recording paused" : "Clipdeck"
        item.button?.setAccessibilityLabel(paused ? "Clipdeck, recording paused" : "Clipdeck")
    }

    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            let front = NSRect(x: 0, y: 0, width: 15.6, height: 11)
            NSColor.black.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect: front.offsetBy(dx: 2.4, dy: 3), xRadius: 2.2, yRadius: 2.2).fill()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: front, xRadius: 2.2, yRadius: 2.2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipdeck"
        return image
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onToggle?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open History", action: #selector(openHistory), keyEquivalent: "")
        if let shortcut = currentShortcut?(), let letter = KeyboardLayout.name(for: shortcut.keyCode).first,
           letter.isLetter, KeyboardLayout.name(for: shortcut.keyCode).count == 1 {
            open.keyEquivalent = String(letter).lowercased()
            open.keyEquivalentModifierMask = Self.flags(shortcut.modifiers)
        }
        let pause = menu.addItem(withTitle: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.state = isPaused ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipdeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.filter { $0.action != #selector(NSApplication.terminate(_:)) }.forEach { $0.target = self }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private static func flags(_ modifiers: ShortcutModifiers) -> NSEvent.ModifierFlags {
        let pairs: [(ShortcutModifiers, NSEvent.ModifierFlags)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        return pairs.filter { modifiers.contains($0.0) }.reduce(into: NSEvent.ModifierFlags()) { $0.formUnion($1.1) }
    }

    @objc private func openHistory() {
        onToggle?()
    }

    @objc private func togglePause() {
        onTogglePause?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
