import Foundation
import os

enum AppEnvironment {
    static let dataDirectoryVariable = "CLIPDECK_DATA_DIR"
    static var showPanelNotification: Notification.Name {
        Notification.Name("dev.clipdeck.Clipdeck.showPanel" + (isTestMode ? ".test" : ""))
    }

    static var showSettingsNotification: Notification.Name {
        Notification.Name("dev.clipdeck.Clipdeck.showSettings" + (isTestMode ? ".test" : ""))
    }

    static var snapshotPath: String? {
        isTestMode ? ProcessInfo.processInfo.environment["CLIPDECK_SNAPSHOT"] : nil
    }

    static var isTestMode: Bool {
        ProcessInfo.processInfo.environment[dataDirectoryVariable] != nil
    }

    static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment[dataDirectoryVariable] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Clipdeck", isDirectory: true)
    }

    static var defaults: UserDefaults {
        isTestMode ? UserDefaults(suiteName: "dev.clipdeck.Clipdeck.e2e") ?? .standard : .standard
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

enum Log {
    static let app = Logger(subsystem: "dev.clipdeck.Clipdeck", category: "app")
    static let watcher = Logger(subsystem: "dev.clipdeck.Clipdeck", category: "watcher")
}
