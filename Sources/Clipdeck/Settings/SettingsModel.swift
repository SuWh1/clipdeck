import AppKit
import ClipdeckCore
import Observation

enum ImportStatus: Equatable {
    case idle
    case running
    case finished(String)
    case failed(String)
}

@Observable
@MainActor
final class SettingsModel {
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored var registerShortcut: ((KeyShortcut) -> Bool)?
    @ObservationIgnored var onRecordingShortcut: ((Bool) -> Void)?
    @ObservationIgnored var onRetentionChange: ((RetentionOption) -> Void)?
    @ObservationIgnored var onPauseChange: ((Bool) -> Void)?
    @ObservationIgnored var onHistoryChanged: (() -> Void)?
    @ObservationIgnored var onClearHistory: (() -> Void)?

    private(set) var shortcut: KeyShortcut
    var shortcutError: String?

    var retention: RetentionOption {
        didSet {
            preferences.retention = retention
            onRetentionChange?(retention)
        }
    }

    var pasteDirectly: Bool {
        didSet { preferences.pasteDirectly = pasteDirectly }
    }

    var isPaused: Bool {
        didSet {
            preferences.isPaused = isPaused
            onPauseChange?(isPaused)
        }
    }

    var ignoredBundleIDs: [String] {
        didSet { preferences.ignoredBundleIDs = ignoredBundleIDs }
    }

    var appearance: PanelAppearance {
        didSet {
            preferences.appearance = appearance
            Self.apply(appearance)
        }
    }

    var theme: PanelTheme {
        didSet { preferences.theme = theme }
    }

    var glass: Double {
        didSet { preferences.glass = glass }
    }

    private(set) var launchAtLogin = false
    private(set) var launchAtLoginMessage: String?
    private(set) var accessibilityTrusted = false
    private(set) var importStatus = ImportStatus.idle
    private(set) var hasCustomPanelPosition = false
    private(set) var isRecordingShortcut = false

    init(preferences: Preferences) {
        self.preferences = preferences
        shortcut = preferences.shortcut
        retention = preferences.retention
        pasteDirectly = preferences.pasteDirectly
        isPaused = preferences.isPaused
        ignoredBundleIDs = preferences.ignoredBundleIDs
        appearance = preferences.appearance
        theme = preferences.theme
        glass = preferences.glass
        Self.apply(appearance)
        refreshStatus()
    }

    private static func apply(_ appearance: PanelAppearance) {
        NSApp?.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func setRecordingShortcut(_ isRecording: Bool) {
        isRecordingShortcut = isRecording
        onRecordingShortcut?(isRecording)
    }

    func applyShortcut(_ candidate: KeyShortcut) {
        guard candidate != shortcut else {
            shortcutError = nil
            return
        }
        if registerShortcut?(candidate) ?? true {
            shortcut = candidate
            preferences.shortcut = candidate
            shortcutError = nil
        } else {
            shortcutError = Self.conflictMessage(for: candidate)
        }
    }

    static func conflictMessage(for shortcut: KeyShortcut) -> String {
        "\(shortcut.displayString) is already used by macOS or another app. Choose a different shortcut."
    }

    func refreshStatus() {
        launchAtLogin = LoginItem.isEnabled
        launchAtLoginMessage = LoginItem.needsApproval
            ? "Turn Clipdeck on in System Settings › General › Login Items."
            : nil
        accessibilityTrusted = AXIsProcessTrusted()
        hasCustomPanelPosition = preferences.panelTopLeft != nil
    }

    func resetPanelPosition() {
        preferences.panelTopLeft = nil
        hasCustomPanelPosition = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            refreshStatus()
        } catch {
            refreshStatus()
            launchAtLoginMessage = "This could not be changed: \(error.localizedDescription)"
        }
    }

    func openAccessibilitySettings() {
        Paster.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func addIgnoredApp(at url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !ignoredBundleIDs.contains(bundleID) else { return }
        ignoredBundleIDs = ignoredBundleIDs + [bundleID]
    }

    func removeIgnoredApp(_ bundleID: String) {
        ignoredBundleIDs = ignoredBundleIDs.filter { $0 != bundleID }
    }

    func clearHistory() {
        onClearHistory?()
    }

    func importPasteNow(from url: URL) {
        importStatus = .running
        let directory = AppEnvironment.dataDirectory
        let classifier = ClipClassifier(ignoredBundleIDs: Set(ignoredBundleIDs))
        let notBefore = retention.policy.cutoff(now: Date())
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportSummary, any Error> in
                Result {
                    try PasteNowImporter(databaseURL: url)
                        .importHistory(into: try HistoryStore(directory: directory), classifier: classifier, notBefore: notBefore)
                }
            }.value
            switch result {
            case .success(let summary):
                importStatus = .finished(summary.description)
                onHistoryChanged?()
            case .failure(let error):
                importStatus = .failed(error.localizedDescription)
            }
        }
    }
}
