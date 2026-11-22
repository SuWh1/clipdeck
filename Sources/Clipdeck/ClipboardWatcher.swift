import AppKit
import ClipdeckCore

@MainActor
final class ClipboardWatcher {
    private static let pollInterval: TimeInterval = 0.25

    var onRecorded: (() -> Void)?

    private let pasteboard = NSPasteboard.general
    private let store: HistoryStore
    private let preferences: Preferences
    private var lastChangeCount = -1
    private var timer: Timer?
    private var pending: Task<Void, Never>?

    init(store: HistoryStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        poll()
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard !preferences.isPaused else { return }
        let snapshot = PasteboardSnapshot(reading: pasteboard)
        let app = NSWorkspace.shared.frontmostApplication
        let source = ClipSource(bundleID: app?.bundleIdentifier, name: app?.localizedName)
        let classifier = ClipClassifier(ignoredBundleIDs: Set(preferences.ignoredBundleIDs))
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            let candidate = await Task.detached(priority: .utility) {
                classifier.classify(snapshot, source: source)
            }.value
            guard let candidate else { return }
            self?.save(candidate)
        }
    }

    private func save(_ candidate: ClipCandidate) {
        do {
            try store.record(candidate)
            onRecorded?()
        } catch {
            Log.watcher.error("Saving a copied \(candidate.kind.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
