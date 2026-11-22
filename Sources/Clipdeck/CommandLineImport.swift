import Foundation
import ClipdeckCore

enum CommandLineImport {
    @MainActor
    static func run(path: String?) -> Int32 {
        let url = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? PasteNowImporter.defaultDatabaseURL
        do {
            let store = try HistoryStore(directory: AppEnvironment.dataDirectory)
            let preferences = Preferences(defaults: AppEnvironment.defaults)
            let summary = try PasteNowImporter(databaseURL: url).importHistory(
                into: store,
                classifier: ClipClassifier(ignoredBundleIDs: Set(preferences.ignoredBundleIDs)),
                notBefore: preferences.retention.policy.cutoff(now: Date())
            )
            print(summary.description)
            return 0
        } catch {
            FileHandle.standardError.write(Data("Import failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
