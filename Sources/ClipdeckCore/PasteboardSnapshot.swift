import AppKit

public struct PasteboardSnapshot: Equatable, Sendable {
    public let types: [String]
    public let string: String?
    public let rtf: Data?
    public let imageData: Data?
    public let fileURLs: [URL]
    public let urlString: String?

    public init(types: [String], string: String?, rtf: Data?, imageData: Data?, fileURLs: [URL], urlString: String?) {
        self.types = types
        self.string = string
        self.rtf = rtf
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.urlString = urlString
    }

    public init(reading pasteboard: NSPasteboard) {
        let types = pasteboard.types ?? []
        let typeNames = types.map(\.rawValue)
        let fileURLs = types.contains(.fileURL)
            ? pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            : []
        let string = pasteboard.string(forType: .string)
        let urlString = pasteboard.string(forType: .URL)
        let needsImage = fileURLs.isEmpty
            && (Self.isBlank(string ?? urlString) || Self.imageComesFirst(typeNames))
        self.init(
            types: typeNames,
            string: string,
            rtf: pasteboard.data(forType: .rtf),
            imageData: needsImage ? pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) : nil,
            fileURLs: fileURLs,
            urlString: urlString
        )
    }

    private static let imageTypes: Set<String> = ["public.png", "public.tiff"]
    private static let textTypes: Set<String> = ["public.utf8-plain-text", "public.url", "public.rtf", "public.html"]

    static func imageComesFirst(_ types: [String]) -> Bool {
        let imageIndex = types.firstIndex { imageTypes.contains($0) } ?? Int.max
        let textIndex = types.firstIndex { textTypes.contains($0) } ?? Int.max
        return imageIndex < textIndex
    }

    static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
