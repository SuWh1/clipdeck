import AppKit
import ClipdeckCore

@MainActor
final class StatusItemController: NSObject {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var currentShortcut: (() -> KeyShortcut)?

    private static let savedAnimationDuration: TimeInterval = 0.6

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isPaused = false
    private var animation: Timer?

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

    func playSavedAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, animation?.isValid != true else { return }
        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let finished = MainActor.assumeIsolated { () -> Bool in
                let progress = min(Date().timeIntervalSince(start) / Self.savedAnimationDuration, 1)
                self?.item.button?.image = Self.makeIcon(progress: progress)
                return progress >= 1
            }
            if finished { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    /// At progress 0 the old card is alone in front; it slides back as a new card pops in on top.
    static func makeIcon(progress: CGFloat = 1) -> NSImage {
        let slide = easeOut(min(progress / 0.55, 1))
        let pop = min(max((progress - 0.2) / 0.8, 0), 1)
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: false) { _ in
            let front = NSRect(x: 0, y: 0, width: 15.6, height: 11)
            NSColor.black.withAlphaComponent(1 - 0.6 * slide).setFill()
            NSBezierPath(roundedRect: front.offsetBy(dx: 2.4 * slide, dy: 3 * slide), xRadius: 2.2, yRadius: 2.2).fill()
            let scale = 0.5 + 0.5 * backOut(pop)
            let card = front.insetBy(dx: front.width * (1 - scale) / 2, dy: front.height * (1 - scale) / 2)
            NSColor.black.withAlphaComponent(min(pop * 3, 1)).setFill()
            NSBezierPath(roundedRect: card, xRadius: 2.2 * scale, yRadius: 2.2 * scale).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipdeck"
        return image
    }

    private static func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private static func backOut(_ t: CGFloat) -> CGFloat {
        let overshoot: CGFloat = 0.8
        return 1 + (overshoot + 1) * pow(t - 1, 3) + overshoot * pow(t - 1, 2)
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
