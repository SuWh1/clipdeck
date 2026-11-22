import Foundation

public final class HistoryStore {
    public static let previewLength = 2_000

    private static let schema = """
        PRAGMA journal_mode = WAL;
        PRAGMA secure_delete = ON;
        PRAGMA user_version = 1;
        CREATE TABLE IF NOT EXISTS clips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          text TEXT NOT NULL,
          rtf BLOB,
          imageFile TEXT,
          imageWidth INTEGER NOT NULL DEFAULT 0,
          imageHeight INTEGER NOT NULL DEFAULT 0,
          byteSize INTEGER NOT NULL DEFAULT 0,
          characterCount INTEGER NOT NULL DEFAULT 0,
          contentHash TEXT NOT NULL UNIQUE,
          searchText TEXT NOT NULL,
          sourceBundleID TEXT,
          sourceName TEXT,
          createdAt REAL NOT NULL,
          lastCopiedAt REAL NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          copyCount INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS clips_lastCopiedAt ON clips (lastCopiedAt DESC);
        """
    private static let metadataColumns = """
        id, kind, imageFile, imageWidth, imageHeight, byteSize, characterCount, contentHash,
        sourceBundleID, sourceName, createdAt, lastCopiedAt, pinned, copyCount
        """

    public let directory: URL
    private let imagesDirectory: URL
    private let db: SQLiteDatabase
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        self.directory = directory
        self.imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        self.now = now
        for folder in [directory, imagesDirectory] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        db = try SQLiteDatabase(path: directory.appendingPathComponent("history.sqlite").path)
        try db.execute(Self.schema)
    }

    @discardableResult
    public func record(_ candidate: ClipCandidate, at date: Date? = nil) throws -> ClipItem {
        let time = date ?? now()
        let id = try db.transaction { try upsert(candidate, at: time) }
        return try requireItem(id: id)
    }

    private func upsert(_ candidate: ClipCandidate, at time: Date) throws -> Int64 {
        let hash = candidate.contentHash
        if let existing = try db.query("SELECT id, lastCopiedAt FROM clips WHERE contentHash = ?", [.text(hash)]).first,
           let id = existing.int("id") {
            if time.timeIntervalSinceReferenceDate > existing.double("lastCopiedAt") ?? 0 {
                try db.run(
                    "UPDATE clips SET lastCopiedAt = ?, copyCount = copyCount + 1 WHERE id = ?",
                    [.real(time.timeIntervalSinceReferenceDate), .integer(id)]
                )
            }
            return id
        }
        let imageFile = try saveImage(candidate.image, hash: hash)
        do {
            try insert(candidate, hash: hash, imageFile: imageFile, at: time)
        } catch {
            if let imageFile {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(imageFile))
            }
            throw error
        }
        return db.lastInsertRowID
    }

    private func insert(_ candidate: ClipCandidate, hash: String, imageFile: String?, at time: Date) throws {
        try db.run(
            """
            INSERT INTO clips (kind, text, rtf, imageFile, imageWidth, imageHeight, byteSize, characterCount, contentHash,
              searchText, sourceBundleID, sourceName, createdAt, lastCopiedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(candidate.kind.rawValue), .text(candidate.text), candidate.rtf.map(SQLValue.blob) ?? .null,
                imageFile.map(SQLValue.text) ?? .null, .integer(Int64(candidate.image?.width ?? 0)),
                .integer(Int64(candidate.image?.height ?? 0)), .integer(Int64(candidate.byteSize)),
                .integer(Int64(candidate.text.count)), .text(hash),
                .text(candidate.searchText), candidate.source?.bundleID.map(SQLValue.text) ?? .null,
                candidate.source?.name.map(SQLValue.text) ?? .null,
                .real(time.timeIntervalSinceReferenceDate), .real(time.timeIntervalSinceReferenceDate),
            ]
        )
    }

    public func previews(matching query: HistoryQuery, limit: Int = 1_000) throws -> [ClipItem] {
        let kindClause = query.filter.kind.map { [("kind = ?", SQLValue.text($0.rawValue))] } ?? []
        let pinnedClause = query.filter == .pinned ? [("pinned = 1", SQLValue?.none)] : []
        let searchClauses = query.searchTerms.map { ("instr(searchText, ?) > 0", SQLValue?.some(.text($0))) }
        let clauses: [(String, SQLValue?)] = kindClause.map { ($0.0, $0.1) } + pinnedClause + searchClauses
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.map(\.0).joined(separator: " AND ")
        let sql = """
            SELECT \(Self.metadataColumns), substr(text, 1, \(Self.previewLength)) AS text, NULL AS rtf
            FROM clips \(whereSQL) ORDER BY lastCopiedAt DESC, id DESC LIMIT ?
            """
        let parameters = clauses.compactMap(\.1) + [.integer(Int64(limit))]
        return try db.query(sql, parameters).compactMap(Self.item(from:))
    }

    public func item(id: Int64) throws -> ClipItem? {
        try db.query("SELECT \(Self.metadataColumns), text, rtf FROM clips WHERE id = ?", [.integer(id)])
            .first.flatMap(Self.item(from:))
    }

    public func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    public func setPinned(_ pinned: Bool, id: Int64) throws {
        try db.run("UPDATE clips SET pinned = ? WHERE id = ?", [.integer(pinned ? 1 : 0), .integer(id)])
    }

    public func delete(id: Int64) throws {
        try deleteRows(db.query("SELECT id, imageFile FROM clips WHERE id = ?", [.integer(id)]))
    }

    public func clearUnpinned() throws {
        try deleteRows(db.query("SELECT id, imageFile FROM clips WHERE pinned = 0"))
    }

    @discardableResult
    public func purge(_ policy: RetentionPolicy) throws -> Int {
        let aged = try policy.cutoff(now: now()).map {
            try db.query(
                "SELECT id, imageFile FROM clips WHERE pinned = 0 AND lastCopiedAt < ?",
                [.real($0.timeIntervalSinceReferenceDate)]
            )
        } ?? []
        let overflow = try policy.maxItems.map {
            try db.query(
                """
                SELECT id, imageFile FROM clips WHERE pinned = 0 AND id NOT IN
                  (SELECT id FROM clips WHERE pinned = 0 ORDER BY lastCopiedAt DESC, id DESC LIMIT ?)
                """,
                [.integer(Int64($0))]
            )
        } ?? []
        let unique = Dictionary((aged + overflow).compactMap { row in row.int("id").map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
        try deleteRows(Array(unique.values))
        return unique.count
    }

    public func count() throws -> Int {
        Int(try db.query("SELECT COUNT(*) AS total FROM clips").first?.int("total") ?? 0)
    }

    private func requireItem(id: Int64) throws -> ClipItem {
        guard let item = try item(id: id) else {
            throw SQLiteError(code: 0, message: "clip \(id) disappeared right after it was saved")
        }
        return item
    }

    private func saveImage(_ image: ImagePayload?, hash: String) throws -> String? {
        guard let image else { return nil }
        let name = "\(hash).png"
        try image.png.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    private func deleteRows(_ rows: [SQLRow]) throws {
        let ids = rows.compactMap { $0.int("id") }
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        try db.run("DELETE FROM clips WHERE id IN (\(placeholders))", ids.map(SQLValue.integer))
        for file in rows.compactMap({ $0.string("imageFile") }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }

    private static func item(from row: SQLRow) -> ClipItem? {
        guard let id = row.int("id"), let kind = row.string("kind").flatMap(ClipKind.init(rawValue:)) else { return nil }
        let bundleID = row.string("sourceBundleID")
        let sourceName = row.string("sourceName")
        return ClipItem(
            id: id,
            kind: kind,
            text: row.string("text") ?? "",
            rtf: row.data("rtf"),
            imageFile: row.string("imageFile"),
            imageWidth: Int(row.int("imageWidth") ?? 0),
            imageHeight: Int(row.int("imageHeight") ?? 0),
            byteSize: Int(row.int("byteSize") ?? 0),
            characterCount: Int(row.int("characterCount") ?? 0),
            contentHash: row.string("contentHash") ?? "",
            source: bundleID == nil && sourceName == nil ? nil : ClipSource(bundleID: bundleID, name: sourceName),
            createdAt: Date(timeIntervalSinceReferenceDate: row.double("createdAt") ?? 0),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: row.double("lastCopiedAt") ?? 0),
            isPinned: row.int("pinned") == 1,
            copyCount: Int(row.int("copyCount") ?? 1)
        )
    }
}
