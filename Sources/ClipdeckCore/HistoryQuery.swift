import Foundation

public enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, images, links, files, pinned

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .links: "Links"
        case .files: "Files"
        case .pinned: "Pinned"
        }
    }

    public var symbolName: String {
        switch self {
        case .all: "square.stack"
        case .text: "text.alignleft"
        case .images: "photo"
        case .links: "link"
        case .files: "doc"
        case .pinned: "pin"
        }
    }

    var kind: ClipKind? {
        switch self {
        case .text: .text
        case .images: .image
        case .links: .link
        case .files: .file
        case .all, .pinned: nil
        }
    }
}

public struct HistoryQuery: Equatable, Sendable {
    public let filter: HistoryFilter
    public let search: String

    public init(filter: HistoryFilter = .all, search: String = "") {
        self.filter = filter
        self.search = search
    }

    var searchTerms: [String] {
        SearchFolding.fold(search).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
