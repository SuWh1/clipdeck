import Foundation
import Testing
@testable import ClipdeckCore

private struct PasteNowFixture {
    enum Storage { case inline(compressed: Bool), external, missing, corrupt }

    let directory: URL
    let databaseURL: URL
    let db: SQLiteDatabase

    init() throws {
        directory = makeTempDirectory()
        databaseURL = directory.appendingPathComponent("PasteNow.sqlite")
        db = try SQLiteDatabase(path: databaseURL.path)
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("""
            CREATE TABLE ZPASTEITEM (Z_PK INTEGER PRIMARY KEY, ZBASEUNIFORMTYPE VARCHAR, ZSECONDARYUNIFORMTYPE VARCHAR,
              ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP, ZAPPBUNDLEID VARCHAR, ZITEMDATA INTEGER, ZREMOVEDFROMALL INTEGER);
            CREATE TABLE ZPASTEITEMDATA (Z_PK INTEGER PRIMARY KEY, ZCOMPRESSED INTEGER, ZDATA BLOB, ZPASTEITEM INTEGER);
            """)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
    }

    var externalDirectory: URL {
        directory.appendingPathComponent(".PasteNow_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
    }

    func add(
        id: Int, type: String, text: String? = nil, timestamp: Double, bundleID: String? = "com.apple.Notes",
        representations: [(String, Data)] = [], storage: Storage = .inline(compressed: true), removed: Bool = false
    ) throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: representations.map { ["type": $0.0, "data": $0.1] }, format: .binary, options: 0
        )
        let compressed = try (plist as NSData).compressed(using: .lzfse) as Data
        let blob: SQLValue
        let isCompressed: Bool
        switch storage {
        case .inline(let compress):
            blob = .blob(Data([1]) + (compress ? compressed : plist))
            isCompressed = compress
        case .external:
            let uuid = UUID().uuidString
            try compressed.write(to: externalDirectory.appendingPathComponent(uuid))
            blob = .blob(Data([2]) + Data(uuid.utf8) + Data([0]))
            isCompressed = true
        case .missing:
            blob = .null
            isCompressed = true
        case .corrupt:
            blob = .blob(Data([1, 9, 9, 9]))
            isCompressed = true
        }
        try db.run("INSERT INTO ZPASTEITEMDATA VALUES (?, ?, ?, ?)", [.integer(Int64(id)), .integer(isCompressed ? 1 : 0), blob, .integer(Int64(id))])
        try db.run(
            "INSERT INTO ZPASTEITEM VALUES (?, ?, NULL, ?, ?, ?, ?, ?)",
            [.integer(Int64(id)), .text(type), text.map(SQLValue.text) ?? .null, .real(timestamp),
             bundleID.map(SQLValue.text) ?? .null, .integer(Int64(id)), .integer(removed ? 1 : 0)]
        )
    }
}

@Suite("PasteNowImporter")
struct PasteNowImporterTests {
    private let classifier = ClipClassifier(ignoredBundleIDs: [])
    private let names: @Sendable (String) -> String? = { $0 == "com.apple.Notes" ? "Notes" : nil }

    private func importFixture(_ fixture: PasteNowFixture, into store: HistoryStore, notBefore: Date? = nil) throws -> ImportSummary {
        try PasteNowImporter(databaseURL: fixture.databaseURL, appName: names)
            .importHistory(into: store, classifier: classifier, notBefore: notBefore)
    }

    @Test("should leave out items older than the history limit and count them")
    func tooOld() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", timestamp: 100, representations: [("public.utf8-plain-text", Data("old".utf8))])
        try fixture.add(id: 2, type: "public.text", timestamp: 300, representations: [("public.utf8-plain-text", Data("new".utf8))])
        let store = try makeStore()
        let summary = try importFixture(fixture, into: store, notBefore: Date(timeIntervalSinceReferenceDate: 200))
        #expect(summary == ImportSummary(imported: 1, skipped: 0, tooOld: 1))
        #expect(try store.previews(matching: HistoryQuery()).map(\.text) == ["new"])
    }

    @Test("should refuse external data that is a symbolic link")
    func symlinkedData() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.image", timestamp: 1, representations: [("public.png", TestImages.png())], storage: .external)
        let stored = try #require(FileManager.default.contentsOfDirectory(at: fixture.externalDirectory, includingPropertiesForKeys: nil).first)
        let target = fixture.directory.appendingPathComponent("elsewhere")
        try FileManager.default.moveItem(at: stored, to: target)
        try FileManager.default.createSymbolicLink(at: stored, withDestinationURL: target)
        let store = try makeStore()
        #expect(try importFixture(fixture, into: store) == ImportSummary(imported: 0, skipped: 1, tooOld: 0))
    }

    @Test("should import text, links, images and files with their original times")
    func importsAll() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", timestamp: 100, representations: [("public.utf8-plain-text", Data("hello".utf8))])
        try fixture.add(id: 2, type: "public.url", timestamp: 200, representations: [("public.utf8-plain-text", Data("https://a.com".utf8))])
        try fixture.add(id: 3, type: "public.image", timestamp: 300, representations: [("public.png", TestImages.png())])
        try fixture.add(id: 4, type: "public.file-url", timestamp: 400, representations: [
            ("public.file-url", Data("file:///tmp/a.txt".utf8)), ("public.utf8-plain-text", Data("a.txt".utf8)),
        ])
        let store = try makeStore()
        let summary = try importFixture(fixture, into: store)
        let items = try store.previews(matching: HistoryQuery())
        #expect(summary == ImportSummary(imported: 4, skipped: 0, tooOld: 0))
        #expect(items.map(\.kind) == [.file, .image, .link, .text])
        #expect(items.map(\.text) == ["/tmp/a.txt", "", "https://a.com", "hello"])
        #expect(items.last?.createdAt == Date(timeIntervalSinceReferenceDate: 100))
        #expect(items.last?.source == ClipSource(bundleID: "com.apple.Notes", name: "Notes"))
    }

    @Test("should read data stored outside the database and uncompressed data")
    func storageKinds() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.image", timestamp: 1, representations: [("public.png", TestImages.png(width: 8, height: 8))], storage: .external)
        try fixture.add(id: 2, type: "public.text", timestamp: 2, representations: [("public.utf8-plain-text", Data("raw".utf8))], storage: .inline(compressed: false))
        let store = try makeStore()
        #expect(try importFixture(fixture, into: store) == ImportSummary(imported: 2, skipped: 0, tooOld: 0))
        #expect(try store.previews(matching: HistoryQuery(filter: .images)).first?.imageWidth == 8)
        #expect(try store.previews(matching: HistoryQuery(filter: .text)).map(\.text) == ["raw"])
    }

    @Test("should fall back to the plain text column when the data is missing")
    func fallbackText() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", text: "from column", timestamp: 1, storage: .missing)
        try fixture.add(id: 2, type: "public.url", text: "https://b.com", timestamp: 2, storage: .missing)
        let store = try makeStore()
        #expect(try importFixture(fixture, into: store) == ImportSummary(imported: 2, skipped: 0, tooOld: 0))
        #expect(try store.previews(matching: HistoryQuery()).map(\.kind) == [.link, .text])
    }

    @Test("should skip removed items and unreadable data and count them")
    func skips() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", timestamp: 1, representations: [("public.utf8-plain-text", Data("gone".utf8))], removed: true)
        try fixture.add(id: 2, type: "public.image", timestamp: 2, storage: .corrupt)
        try fixture.add(id: 3, type: "public.text", timestamp: 3, representations: [("public.utf8-plain-text", Data("ok".utf8))])
        let store = try makeStore()
        #expect(try importFixture(fixture, into: store) == ImportSummary(imported: 1, skipped: 2, tooOld: 0))
    }

    @Test("should use the stored path for copied files")
    func storedFilePath() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.file-url", text: "/Users/me/report.pdf", timestamp: 1, storage: .missing)
        let store = try makeStore()
        _ = try importFixture(fixture, into: store)
        #expect(try store.previews(matching: HistoryQuery(filter: .files)).first?.filePaths == ["/Users/me/report.pdf"])
    }

    @Test("should not duplicate items when importing twice")
    func twice() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", timestamp: 1, representations: [("public.utf8-plain-text", Data("once".utf8))])
        let store = try makeStore()
        _ = try importFixture(fixture, into: store)
        _ = try importFixture(fixture, into: store)
        #expect(try store.count() == 1)
    }

    @Test("should include recent items that are still in the write-ahead log")
    func writeAheadLog() throws {
        let fixture = try PasteNowFixture()
        try fixture.add(id: 1, type: "public.text", timestamp: 1, representations: [("public.utf8-plain-text", Data("recent".utf8))])
        #expect(FileManager.default.fileExists(atPath: fixture.databaseURL.path + "-wal"))
        let store = try makeStore()
        #expect(try importFixture(fixture, into: store).imported == 1)
    }

    @Test("should refuse a file that is not a PasteNow database")
    func notPasteNow() throws {
        let url = makeTempDirectory().appendingPathComponent("other.sqlite")
        try SQLiteDatabase(path: url.path).execute("CREATE TABLE other (a)")
        #expect(throws: PasteNowImportError.notPasteNowDatabase) {
            try PasteNowImporter(databaseURL: url).importHistory(into: try makeStore(), classifier: classifier)
        }
    }

    @Test("should explain when the file does not exist")
    func missingFile() throws {
        let url = makeTempDirectory().appendingPathComponent("nope.sqlite")
        #expect(throws: PasteNowImportError.self) {
            try PasteNowImporter(databaseURL: url).importHistory(into: try makeStore(), classifier: classifier)
        }
        #expect(PasteNowImportError.fileNotFound(url.path).errorDescription?.contains("nope.sqlite") == true)
    }
}
