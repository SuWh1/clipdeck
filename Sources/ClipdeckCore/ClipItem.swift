import Foundation

public struct ClipItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let kind: ClipKind
    public let text: String
    public let rtf: Data?
    public let imageFile: String?
    public let imageWidth: Int
    public let imageHeight: Int
    public let byteSize: Int
    public let characterCount: Int
    public let contentHash: String
    public let source: ClipSource?
    public let createdAt: Date
    public let lastCopiedAt: Date
    public let isPinned: Bool
    public let copyCount: Int

    public var filePaths: [String] {
        kind == .file ? text.components(separatedBy: "\n").filter { !$0.isEmpty } : []
    }
}
