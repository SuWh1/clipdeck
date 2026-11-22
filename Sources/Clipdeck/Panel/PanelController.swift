import AppKit
import Carbon.HIToolbox
import ClipdeckCore
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 364
    private static let maxHeight: CGFloat = 660
    private static let cornerRadius: CGFloat = 24
    private static let reopenGuard: TimeInterval = 0.3
    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    var onPaste: ((ClipItem, PasteMode, pid_t?) -> Void)?

    private let history: HistoryModel
    private let preferences: Preferences
    private let settings: SettingsModel
    private let router = PanelRouter()
    private var hosting: NSView?
    private var isDetached = false
    private let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: maxHeight))
    private var keyMonitor: Any?
    private var lastHiddenAt = Date.distantPast
    private var targetProcess: pid_t?
    private var movedByUser = false

    init(history: HistoryModel, preferences: Preferences, settings: SettingsModel) {
        self.history = history
        self.preferences = preferences
        self.settings = settings
        super.init()
        let actions = PanelActions(
            paste: { [weak self] item, mode in self?.paste(item, mode: mode) },
            openSettings: { [weak self] in self?.showSettings() },
            showHistory: { [weak self] in self?.router.page = .history },
            panelMoved: { [weak self] in self?.movedByUser = true },
            runDetached: { [weak self] body in self?.runDetached(body) }
        )
        let root = PanelRootView(history: history, settings: settings, router: router, actions: actions)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        self.hosting = hosting
        panel.contentView = GlassContainer.make(content: hosting, cornerRadius: Self.cornerRadius)
        panel.delegate = self
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle(fromStatusItem: Bool = false) {
        if panel.isVisible {
            hide()
        } else if !fromStatusItem || Date().timeIntervalSince(lastHiddenAt) > Self.reopenGuard {
            show()
        }
    }

    func show() {
        guard !panel.isVisible else { return }
        targetProcess = NSWorkspace.shared.frontmostApplication?.processIdentifier
        history.prepareForShow()
        let frame = targetFrame()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.1 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        scheduleSnapshot()
    }

    func showSettings() {
        if !panel.isVisible {
            show()
        }
        router.page = .settings
        scheduleSnapshot()
    }

    private func runDetached(_ body: () -> Void) {
        isDetached = true
        panel.orderOut(nil)
        NSApp.activate()
        body()
        isDetached = false
        panel.makeKeyAndOrderFront(nil)
    }

    private func scheduleSnapshot() {
        guard let path = AppEnvironment.snapshotPath else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            saveSnapshot(to: path)
        }
    }

    private func saveSnapshot(to path: String) {
        guard let view = hosting, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            Log.app.error("The panel could not be captured for a snapshot")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        } catch {
            Log.app.error("Saving the panel snapshot failed: \(String(describing: error), privacy: .public)")
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        if movedByUser {
            preferences.panelTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
            movedByUser = false
        }
        removeKeyMonitor()
        lastHiddenAt = Date()
        panel.orderOut(nil)
        router.page = .history
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isDetached {
            hide()
        }
    }

    private func paste(_ item: ClipItem, mode: PasteMode) {
        hide()
        onPaste?(item, mode, targetProcess)
    }

    private func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let mouseScreen = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return NSRect(x: 0, y: 0, width: Self.width, height: Self.maxHeight)
        }
        return PanelPlacement.frame(
            size: CGSize(width: Self.width, height: Self.maxHeight),
            savedTopLeft: preferences.panelTopLeft,
            screens: screens.map(\.visibleFrame),
            mouseScreen: mouseScreen.visibleFrame
        )
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func consumes(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        if router.page == .settings {
            guard Int(event.keyCode) == kVK_Escape, !settings.isRecordingShortcut else { return false }
            router.page = .history
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let keyCode = Int(event.keyCode)
        switch keyCode {
        case kVK_Escape:
            if history.search.isEmpty { hide() } else { history.search = "" }
        case kVK_DownArrow:
            history.moveSelection(by: 1)
        case kVK_UpArrow:
            history.moveSelection(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = history.selectedItem {
                paste(item, mode: flags.contains(.command) ? .copyOnly : flags.contains(.shift) ? .plainText : .normal)
            }
        case kVK_Tab:
            history.cycleFilter(by: flags.contains(.shift) ? -1 : 1)
        default:
            return flags == .command && handleCommand(keyCode: keyCode)
        }
        return true
    }

    private func handleCommand(keyCode: Int) -> Bool {
        if let index = Self.digitKeyCodes.firstIndex(of: keyCode) {
            if let item = history.item(at: index) {
                paste(item, mode: .normal)
            }
            return true
        }
        switch keyCode {
        case kVK_ANSI_P:
            if let item = history.selectedItem { history.togglePin(item) }
        case kVK_Delete where history.search.isEmpty:
            guard let item = history.selectedItem else { break }
            if item.isPinned {
                NSSound.beep()
            } else {
                history.delete(item)
            }
        case kVK_ANSI_Comma:
            showSettings()
        default:
            return false
        }
        return true
    }
}
