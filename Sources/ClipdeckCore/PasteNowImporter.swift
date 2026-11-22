import AppKit
import Foundation

public struct ImportSummary: Equatable, Sendable {
    public let imported: Int
    public let skipped: Int
    public let tooOld: Int

    public init(imported: Int, skipped: Int, tooOld: Int) {
        self.imported = imported
        self.skipped = skipped
        self.tooOld = tooOld
    }

    public var description: String {
        let parts = [
            "Imported \(imported) items",
            tooOld > 0 ? "\(tooOld) were older than your history limit" : nil,
            skipped > 0 ? "\(skipped) could not be read" : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: ", ") + "."
    }
}

public enum PasteNowImportError: LocalizedError, Equatable {
    case fileNotFound(String)
    case notPasteNowDatabase
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): "No PasteNow history was found at \(path)."
        case .notPasteNowDatabase: "This file is not a PasteNow history database."
        case .unreadable(let reason): "The PasteNow history could not be read: \(reason)"
        }
    }
}

public enum AppNames {
    public static func localizedName(for bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.deletingPathExtension().lastPathComponent
    }
}

public struct PasteNowImporter {
    public static let defaultDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/KAQ3M6FSM7.app.pastenow.PasteNow/Documents/PasteNow.sqlite")

    private static let itemsSQL = """
        SELECT i.ZBASEUNIFORMTYPE AS type, i.ZTEXT AS text, i.ZTIMESTAMP AS timestamp, i.ZAPPBUNDLEID AS bundleID,
               i.ZREMOVEDFROMALL AS removed, d.ZDATA AS data, d.ZCOMPRESSED AS compressed
        FROM ZPASTEITEM i LEFT JOIN ZPASTEITEMDATA d ON d.Z_PK = i.ZITEMDATA
        ORDER BY i.ZTIMESTAMP ASC
        """

    private let databaseURL: URL
    private let appName: (String) -> String?

    public init(databaseURL: URL, appName: @escaping (String) -> String? = AppNames.localizedName(for:)) {
        self.databaseURL = databaseURL
        self.appName = appName
    }

    private var externalDirectory: URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(".PasteNow_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
    }

    public func importHistory(into store: HistoryStore, classifier: ClipClassifier, notBefore: Date? = nil) throws -> ImportSummary {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw PasteNowImportError.fileNotFound(databaseURL.path)
        }
        let rows = try readRows()
        let cutoff = notBefore?.timeIntervalSinceReferenceDate ?? -Double.infinity
        let recent = rows.filter { ($0.double("timestamp") ?? 0) >= cutoff }
        let results = try recent.map { try importRow($0, into: store, classifier: classifier) }
        let imported = results.filter { $0 }.count
        return ImportSummary(imported: imported, skipped: results.count - imported, tooOld: rows.count - recent.count)
    }

    private func readRows() throws -> [SQLRow] {
        let workingCopy = try copyToTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: workingCopy.deletingLastPathComponent()) }
        do {
            let db = try SQLiteDatabase(path: workingCopy.path)
            try db.execute("PRAGMA trusted_schema = OFF; PRAGMA query_only = ON;")
            let tables = try db.query(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('ZPASTEITEM', 'ZPASTEITEMDATA')"
            )
            guard tables.count == 2 else { throw PasteNowImportError.notPasteNowDatabase }
            return try db.query(Self.itemsSQL)
        } catch let error as PasteNowImportError {
            throw error
        } catch {
            throw PasteNowImportError.unreadable(String(describing: error))
        }
    }

    // A live PasteNow keeps recent items in its -wal file, so the database is read from a full copy.
    private func copyToTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipdeck-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(databaseURL.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: databaseURL.path + suffix) {
            try FileManager.default.copyItem(atPath: databaseURL.path + suffix, toPath: target.path + suffix)
        }
        return target
    }

    private func importRow(_ row: SQLRow, into store: HistoryStore, classifier: ClipClassifier) throws -> Bool {
        guard row.int("removed") != 1, let timestamp = row.double("timestamp") else { return false }
        let source = row.string("bundleID").map { ClipSource(bundleID: $0, name: appName($0)) }
        guard let snapshot = snapshot(for: row), let candidate = classifier.classify(snapshot, source: source) else {
            return false
        }
        try store.record(candidate, at: Date(timeIntervalSinceReferenceDate: timestamp))
        return true
    }

    private func snapshot(for row: SQLRow) -> PasteboardSnapshot? {
        let type = row.string("type") ?? ""
        let text = row.string("text")
        if type == "public.file-url", let text, text.hasPrefix("/") {
            let urls = text.components(separatedBy: "\n").filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
            return PasteboardSnapshot(types: [type], string: nil, rtf: nil, imageData: nil, fileURLs: urls, urlString: nil)
        }
        if let blob = row.data("data") {
            return PasteNowPayload.representations(from: blob, compressed: row.int("compressed") != 0, externalDirectory: externalDirectory)
                .map(PasteNowPayload.snapshot(from:))
        }
        guard let text else { return nil }
        return type == "public.url"
            ? PasteboardSnapshot(types: [type], string: nil, rtf: nil, imageData: nil, fileURLs: [], urlString: text)
            : PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text, rtf: nil, imageData: nil, fileURLs: [], urlString: nil)
    }
}

enum PasteNowPayload {
    struct Representation {
        let type: String
        let data: Data
    }

    private static let inlineMarker: UInt8 = 1
    private static let externalMarker: UInt8 = 2
    private static let maxExternalBytes = 200 * 1024 * 1024

    static func representations(from blob: Data, compressed: Bool, externalDirectory: URL) -> [Representation]? {
        guard let stored = storedBytes(blob, externalDirectory: externalDirectory),
              let plistData = compressed ? try? (stored as NSData).decompressed(using: .lzfse) as Data : stored,
              let entries = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [[String: Any]]
        else { return nil }
        return entries.compactMap { entry in
            guard let type = entry["type"] as? String, let data = entry["data"] as? Data else { return nil }
            return Representation(type: type, data: data)
        }
    }

    static func snapshot(from representations: [Representation]) -> PasteboardSnapshot {
        let byType = Dictionary(representations.map { ($0.type, $0.data) }, uniquingKeysWith: { first, _ in first })
        let fileURLs = representations
            .filter { $0.type == "public.file-url" }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
            .compactMap { ($0 as NSURL).isFileReferenceURL() ? ($0 as NSURL).filePathURL : $0 }
            .filter(\.isFileURL)
        return PasteboardSnapshot(
            types: representations.map(\.type),
            string: byType["public.utf8-plain-text"].map { String(decoding: $0, as: UTF8.self) },
            rtf: byType["public.rtf"],
            imageData: byType["public.png"] ?? byType["public.tiff"],
            fileURLs: fileURLs,
            urlString: byType["public.url"].map { String(decoding: $0, as: UTF8.self) }
        )
    }

    // Core Data's external-storage format: 0x01 + bytes inline, or 0x02 + file UUID stored beside the database.
    private static func storedBytes(_ blob: Data, externalDirectory: URL) -> Data? {
        switch blob.first {
        case inlineMarker:
            return Data(blob.dropFirst())
        case externalMarker:
            let name = String(decoding: blob.dropFirst().prefix { $0 != 0 }, as: UTF8.self)
            guard UUID(uuidString: name) != nil else { return nil }
            let url = externalDirectory.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values?.isSymbolicLink == false, (values?.fileSize ?? .max) <= maxExternalBytes else { return nil }
            return try? Data(contentsOf: url)
        default:
            return nil
        }
    }
}
