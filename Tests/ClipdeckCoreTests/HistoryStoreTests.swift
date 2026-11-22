import Foundation
import Testing
@testable import ClipdeckCore

@Suite("HistoryStore")
struct HistoryStoreTests {
    @Test("should record a new text item and list it")
    func recordText() throws {
        let store = try makeStore()
        let item = try store.record(textCandidate("hello"))
        let items = try store.previews(matching: HistoryQuery())
        #expect(items.map(\.id) == [item.id])
        #expect(items.first?.text == "hello")
        #expect(items.first?.kind == .text)
        #expect(items.first?.source == notesSource)
        #expect(items.first?.copyCount == 1)
        #expect(items.first?.characterCount == 5)
    }

    @Test("should list the most recent copy first")
    func order() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        try store.record(textCandidate("first"))
        clock.advance(by: 1)
        try store.record(textCandidate("second"))
        #expect(try store.previews(matching: HistoryQuery()).map(\.text) == ["second", "first"])
    }

    @Test("should move a repeated copy to the top instead of duplicating it")
    func dedupe() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let first = try store.record(textCandidate("same"))
        clock.advance(by: 1)
        try store.record(textCandidate("other"))
        clock.advance(by: 1)
        let again = try store.record(textCandidate("same", source: ClipSource(bundleID: "x", name: "X")))
        let items = try store.previews(matching: HistoryQuery())
        #expect(again.id == first.id)
        #expect(items.map(\.text) == ["same", "other"])
        #expect(items.first?.copyCount == 2)
        #expect(items.first?.source == notesSource)
        #expect(items.first?.lastCopiedAt == clock.now)
        #expect(items.first?.createdAt == first.createdAt)
    }

    @Test("should keep the original time when recording with an explicit date")
    func explicitDate() throws {
        let store = try makeStore()
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let item = try store.record(textCandidate("old"), at: date)
        #expect(item.createdAt == date)
        #expect(item.lastCopiedAt == date)
    }

    @Test("should save images as files and expose their location")
    func image() throws {
        let store = try makeStore()
        let candidate = imageCandidate(width: 6, height: 2)
        let item = try store.record(candidate)
        let url = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: url) == candidate.image?.png)
        #expect(item.imageWidth == 6)
        #expect(item.imageHeight == 2)
        #expect(item.byteSize == candidate.image?.png.count)
        #expect(store.imageURL(for: try store.record(textCandidate("t"))) == nil)
    }

    @Test("should filter by type", arguments: [
        (HistoryFilter.text, ["note"]), (.links, ["https://a.com"]),
        (.files, ["/tmp/a"]), (.images, [""]), (.all, ["/tmp/a", "https://a.com", "", "note"]),
    ])
    func filter(filter: HistoryFilter, expected: [String]) throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        try store.record(textCandidate("note"))
        clock.advance(by: 1)
        try store.record(imageCandidate())
        clock.advance(by: 1)
        try store.record(ClipCandidate(kind: .link, text: "https://a.com"))
        clock.advance(by: 1)
        try store.record(ClipCandidate(kind: .file, text: "/tmp/a"))
        #expect(try store.previews(matching: HistoryQuery(filter: filter)).map(\.text) == expected)
    }

    @Test("should show only pinned items in the pinned filter")
    func pinned() throws {
        let store = try makeStore()
        let a = try store.record(textCandidate("a"))
        try store.record(textCandidate("b"))
        try store.setPinned(true, id: a.id)
        let pinned = try store.previews(matching: HistoryQuery(filter: .pinned))
        #expect(pinned.map(\.text) == ["a"])
        #expect(pinned.first?.isPinned == true)
        try store.setPinned(false, id: a.id)
        #expect(try store.previews(matching: HistoryQuery(filter: .pinned)).isEmpty)
    }

    @Test("should search without caring about case or accents, also in Cyrillic", arguments: [
        "hello", "HELLO", "привет", "ПРИВЕТ", "cafe", "CAFÉ",
    ])
    func search(term: String) throws {
        let store = try makeStore()
        try store.record(textCandidate("Hello Привет Café"))
        try store.record(textCandidate("unrelated"))
        #expect(try store.previews(matching: HistoryQuery(search: term)).map(\.text) == ["Hello Привет Café"])
    }

    @Test("should require every search word to match")
    func searchWords() throws {
        let store = try makeStore()
        try store.record(textCandidate("red apple"))
        try store.record(textCandidate("red car"))
        #expect(try store.previews(matching: HistoryQuery(search: "  apple   red ")).map(\.text) == ["red apple"])
    }

    @Test("should find items by the app they were copied from")
    func searchApp() throws {
        let store = try makeStore()
        try store.record(imageCandidate())
        try store.record(textCandidate("x"))
        #expect(try store.previews(matching: HistoryQuery(search: "preview")).map(\.kind) == [.image])
    }

    @Test("should combine a filter with a search")
    func filterAndSearch() throws {
        let store = try makeStore()
        try store.record(textCandidate("https note"))
        try store.record(ClipCandidate(kind: .link, text: "https://notes.com"))
        let result = try store.previews(matching: HistoryQuery(filter: .links, search: "note"))
        #expect(result.map(\.text) == ["https://notes.com"])
    }

    @Test("should limit how many previews are returned")
    func limit() throws {
        let store = try makeStore()
        for index in 0..<5 { try store.record(textCandidate("item \(index)")) }
        #expect(try store.previews(matching: HistoryQuery(), limit: 2).count == 2)
    }

    @Test("should shorten long text in previews but return it whole by id")
    func previewTruncation() throws {
        let store = try makeStore()
        let long = String(repeating: "abc", count: 5_000)
        let item = try store.record(textCandidate(long))
        let preview = try #require(store.previews(matching: HistoryQuery()).first)
        #expect(preview.text.count == HistoryStore.previewLength)
        #expect(preview.characterCount == long.count)
        #expect(try store.item(id: item.id)?.text == long)
    }

    @Test("should return nil for an unknown id")
    func unknownID() throws {
        #expect(try makeStore().item(id: 999) == nil)
    }

    @Test("should delete an item together with its image file")
    func delete() throws {
        let store = try makeStore()
        let item = try store.record(imageCandidate())
        let url = try #require(store.imageURL(for: item))
        try store.delete(id: item.id)
        #expect(try store.count() == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("should clear unpinned items and keep pinned ones")
    func clear() throws {
        let store = try makeStore()
        let keep = try store.record(textCandidate("keep"))
        let image = try store.record(imageCandidate())
        let imageURL = try #require(store.imageURL(for: image))
        try store.setPinned(true, id: keep.id)
        try store.clearUnpinned()
        #expect(try store.previews(matching: HistoryQuery()).map(\.text) == ["keep"])
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test("should remove items older than the retention time but keep pinned ones")
    func purgeByAge() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let old = try store.record(textCandidate("old"))
        let pinnedOld = try store.record(textCandidate("pinned old"))
        try store.setPinned(true, id: pinnedOld.id)
        clock.advance(by: 3 * 86_400)
        try store.record(textCandidate("new"))
        let removed = try store.purge(RetentionPolicy(maxAge: 2 * 86_400, maxItems: nil))
        #expect(removed == 1)
        #expect(try store.item(id: old.id) == nil)
        #expect(Set(try store.previews(matching: HistoryQuery()).map(\.text)) == ["new", "pinned old"])
    }

    @Test("should remove the oldest unpinned items beyond the item limit")
    func purgeByCount() throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let pinned = try store.record(textCandidate("pinned"))
        try store.setPinned(true, id: pinned.id)
        for index in 0..<4 {
            clock.advance(by: 1)
            try store.record(textCandidate("item \(index)"))
        }
        let removed = try store.purge(RetentionPolicy(maxAge: nil, maxItems: 2))
        #expect(removed == 2)
        #expect(try store.previews(matching: HistoryQuery()).map(\.text) == ["item 3", "item 2", "pinned"])
    }

    @Test("should keep history after the store is opened again")
    func persistence() throws {
        let directory = makeTempDirectory()
        do {
            let store = try makeStore(directory: directory)
            try store.record(textCandidate("saved"))
        }
        let reopened = try makeStore(directory: directory)
        #expect(try reopened.previews(matching: HistoryQuery()).map(\.text) == ["saved"])
    }

    @Test("should count all stored items")
    func count() throws {
        let store = try makeStore()
        try store.record(textCandidate("a"))
        try store.record(imageCandidate())
        #expect(try store.count() == 2)
    }

    @Test("should keep the history folder private to the user")
    func privateFolder() throws {
        let directory = makeTempDirectory().appendingPathComponent("history")
        let store = try makeStore(directory: directory)
        try store.record(imageCandidate())
        for path in [directory.path, directory.appendingPathComponent("images").path] {
            let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
            #expect(permissions == 0o700)
        }
    }

    @Test("should keep the stored text whole even when it contains a null character")
    func nullCharacter() throws {
        let store = try makeStore()
        let item = try store.record(textCandidate("a\u{0}b"))
        #expect(try store.item(id: item.id)?.text == "a\u{0}b")
    }

    @Test("should fail with a readable error when the folder cannot be created")
    func badDirectory() {
        let file = makeTempDirectory().appendingPathComponent("file")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(throws: (any Error).self) { try HistoryStore(directory: file.appendingPathComponent("sub")) }
    }
}

@Suite("HistoryFilter")
struct HistoryFilterTests {
    @Test("should give every filter a title and an icon")
    func labels() {
        for filter in HistoryFilter.allCases {
            #expect(!filter.title.isEmpty)
            #expect(!filter.symbolName.isEmpty)
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("should map type filters to clip kinds and leave the others open")
    func kinds() {
        #expect(HistoryFilter.images.kind == .image)
        #expect(HistoryFilter.all.kind == nil)
        #expect(HistoryFilter.pinned.kind == nil)
    }
}

@Suite("RetentionPolicy")
struct RetentionPolicyTests {
    @Test("should compute the cutoff date from the maximum age")
    func cutoff() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(RetentionPolicy(maxAge: 100, maxItems: nil).cutoff(now: now) == Date(timeIntervalSinceReferenceDate: 900))
        #expect(RetentionPolicy(maxAge: nil, maxItems: nil).cutoff(now: now) == nil)
    }

    @Test("should map every retention option to a policy with a title")
    func options() {
        for option in RetentionOption.allCases {
            #expect(!option.title.isEmpty)
            #expect(option.policy.maxItems == RetentionOption.maxItems)
        }
        #expect(RetentionOption.forever.policy.maxAge == nil)
        #expect(RetentionOption.oneWeek.policy.maxAge == TimeInterval(7 * 86_400))
    }
}

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {
    @Test("should report a readable error for invalid SQL")
    func badSQL() throws {
        let db = try SQLiteDatabase(path: makeTempDirectory().appendingPathComponent("t.sqlite").path)
        #expect(throws: SQLiteError.self) { try db.execute("NOT SQL") }
        do {
            try db.execute("NOT SQL")
        } catch let error as SQLiteError {
            #expect(error.description.contains("syntax error"))
        }
    }

    @Test("should round-trip every value type")
    func values() throws {
        let db = try SQLiteDatabase(path: makeTempDirectory().appendingPathComponent("t.sqlite").path)
        try db.execute("CREATE TABLE t (a, b, c, d, e)")
        try db.run("INSERT INTO t VALUES (?, ?, ?, ?, ?)", [.integer(7), .real(1.5), .text("x"), .blob(Data([1, 2])), .null])
        let row = try #require(db.query("SELECT * FROM t").first)
        #expect(row.int("a") == 7)
        #expect(row.double("b") == 1.5)
        #expect(row.string("c") == "x")
        #expect(row.data("d") == Data([1, 2]))
        #expect(row.string("e") == nil)
        #expect(row.int("missing") == nil)
    }
}
