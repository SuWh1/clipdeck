import AppKit
import ClipdeckCore

@MainActor
final class AppController {
    private static let purgeInterval: TimeInterval = 3_600

    private let preferences: Preferences
    private let store: HistoryStore
    private let history: HistoryModel
    private let settings: SettingsModel
    private let watcher: ClipboardWatcher
    private let hotKeys = HotKeyCenter()
    private let panel: PanelController
    private let statusItem = StatusItemController()
    private var purgeTimer: Timer?
    private var showRequests: ShowRequestListener?

    init() throws {
        let preferences = Preferences(defaults: AppEnvironment.defaults)
        let store = try HistoryStore(directory: AppEnvironment.dataDirectory)
        let history = HistoryModel(store: store)
        self.preferences = preferences
        self.store = store
        self.history = history
        watcher = ClipboardWatcher(store: store, preferences: preferences)
        let settings = SettingsModel(preferences: preferences)
        self.settings = settings
        panel = PanelController(history: history, preferences: preferences, settings: settings)
    }

    func start() {
        wireCallbacks()
        let hasShortcut = registerCurrentShortcut()
        statusItem.setPaused(settings.isPaused)
        watcher.start()
        purge()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: Self.purgeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        showRequests = ShowRequestListener(
            onShow: { [weak self] in self?.panel.show() },
            onSettings: { [weak self] in self?.panel.showSettings() }
        )
        handleFirstLaunch()
        if !hasShortcut && !AppEnvironment.isTestMode {
            showSettings()
        }
    }

    func showPanel() {
        panel.show()
    }

    func showSettings() {
        panel.showSettings()
    }

    private func wireCallbacks() {
        watcher.onRecorded = { [weak self] in
            self?.historyChanged()
            self?.statusItem.playSavedAnimation()
        }
        hotKeys.onPress = { [weak self] in self?.panel.toggle() }
        panel.onPaste = { [weak self] item, mode, target in self?.paste(item, mode: mode, target: target) }
        statusItem.onToggle = { [weak self] in self?.panel.toggle(fromStatusItem: true) }
        statusItem.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem.onTogglePause = { [weak self] in self?.settings.isPaused.toggle() }
        statusItem.currentShortcut = { [weak self] in self?.settings.shortcut ?? .standard }
        settings.registerShortcut = { [weak self] shortcut in self?.hotKeys.register(shortcut) ?? false }
        settings.onRecordingShortcut = { [weak self] isRecording in
            guard let self else { return }
            if isRecording {
                hotKeys.unregister()
            } else {
                registerCurrentShortcut()
            }
        }
        settings.onRetentionChange = { [weak self] _ in self?.purge() }
        settings.onPauseChange = { [weak self] paused in self?.statusItem.setPaused(paused) }
        settings.onHistoryChanged = { [weak self] in self?.history.reload() }
        settings.onClearHistory = { [weak self] in self?.history.clearUnpinned() }
    }

    @discardableResult
    private func registerCurrentShortcut() -> Bool {
        let registered = hotKeys.register(settings.shortcut)
        settings.shortcutError = registered ? nil : SettingsModel.conflictMessage(for: settings.shortcut)
        return registered
    }

    private func paste(_ item: ClipItem, mode: PasteMode, target: pid_t?) {
        let autoPaste = mode != .copyOnly && settings.pasteDirectly
        let outcome = Paster.paste(
            itemID: item.id, store: store, plainText: mode == .plainText, autoPaste: autoPaste, targetProcess: target
        )
        switch outcome {
        case .pasted, .copied:
            break
        case .needsPermission:
            settings.refreshStatus()
        case .failed(let message):
            showAlert(title: "Could not paste", message: message)
        }
    }

    private func historyChanged() {
        if panel.isVisible {
            history.reload()
        }
    }

    private func purge() {
        do {
            if try store.purge(settings.retention.policy) > 0 {
                historyChanged()
            }
        } catch {
            Log.app.error("Cleaning old history failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleFirstLaunch() {
        guard !preferences.hasLaunchedBefore else { return }
        preferences.hasLaunchedBefore = true
        guard !AppEnvironment.isTestMode else { return }
        settings.setLaunchAtLogin(true)
        showSettings()
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
private final class ShowRequestListener: NSObject {
    private let onShow: () -> Void
    private let onSettings: () -> Void

    init(onShow: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onShow = onShow
        self.onSettings = onSettings
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(showRequested), name: AppEnvironment.showPanelNotification,
            object: nil, suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self, selector: #selector(settingsRequested), name: AppEnvironment.showSettingsNotification,
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func showRequested() {
        onShow()
    }

    @objc private func settingsRequested() {
        onSettings()
    }
}
