import AppKit

public enum PasteboardWriter {
    @discardableResult
    public static func write(_ item: ClipItem, imageData: Data?, plainTextOnly: Bool, to pasteboard: NSPasteboard) -> Bool {
        switch item.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
            if let rtf = item.rtf, !plainTextOnly {
                pasteboard.setData(rtf, forType: .rtf)
            }
        case .link:
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
            if !plainTextOnly {
                pasteboard.setString(item.text, forType: .URL)
            }
        case .image:
            guard let imageData, let tiff = ImageEncoding.tiff(fromPNG: imageData) else { return false }
            pasteboard.clearContents()
            pasteboard.setData(imageData, forType: .png)
            pasteboard.setData(tiff, forType: .tiff)
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
        }
        return true
    }
}
