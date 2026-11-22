import CryptoKit
import Foundation

public enum ClipKind: String, CaseIterable, Sendable {
    case text, link, image, file
}

public struct ClipSource: Hashable, Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct ImagePayload: Equatable, Sendable {
    public let png: Data
    public let width: Int
    public let height: Int

    public init(png: Data, width: Int, height: Int) {
        self.png = png
        self.width = width
        self.height = height
    }
}

public struct ClipCandidate: Equatable, Sendable {
    // shortcut: search covers the first 100k characters of a clip, raise it if people search inside huge pastes
    static let searchableLength = 100_000

    public let kind: ClipKind
    public let text: String
    public let rtf: Data?
    public let image: ImagePayload?
    public let source: ClipSource?

    public init(kind: ClipKind, text: String, rtf: Data? = nil, image: ImagePayload? = nil, source: ClipSource? = nil) {
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.image = image
        self.source = source
    }

    public var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(text.utf8))
        if let image {
            hasher.update(data: image.png)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public var filePaths: [String] {
        kind == .file ? text.components(separatedBy: "\n").filter { !$0.isEmpty } : []
    }

    public var searchText: String {
        let parts = [String(text.prefix(Self.searchableLength)), source?.name ?? ""].filter { !$0.isEmpty }
        return SearchFolding.fold(parts.joined(separator: "\n"))
    }

    public var byteSize: Int {
        image?.png.count ?? text.utf8.count
    }
}

enum SearchFolding {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
