import ClipdeckCore
import SwiftUI

struct ClipPreview: View {
    let item: ClipItem
    let imageURL: URL?

    var body: some View {
        switch item.kind {
        case .text:
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            LinkPreview(address: item.text)
        case .image:
            ThumbnailView(url: imageURL, width: item.imageWidth, height: item.imageHeight)
        case .file:
            FilePreview(paths: item.filePaths)
        }
    }
}

private struct LinkPreview: View {
    let address: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(host).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(address)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var host: String {
        let host = URL(string: address)?.host ?? address
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

private struct FilePreview: View {
    let paths: [String]

    var body: some View {
        HStack(spacing: 10) {
            if let first = paths.first {
                Image(nsImage: AppIcons.icon(forFile: first))
                    .resizable()
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private var name: String {
        paths.first.map { ($0 as NSString).lastPathComponent } ?? ""
    }

    private var subtitle: String {
        if paths.count > 1 { return "and \(paths.count - 1) more" }
        return paths.first.map { (($0 as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath } ?? ""
    }
}

private struct ThumbnailView: View {
    private static let maxSize = CGSize(width: 324, height: 150)

    let url: URL?
    let width: Int
    let height: Int
    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let size = displaySize
        ZStack {
            shape.fill(.primary.opacity(0.06))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) { image = await ThumbnailCache.shared.image(for: url) }
        .accessibilityLabel("Image, \(width) by \(height) pixels")
    }

    private var displaySize: CGSize {
        guard width > 0, height > 0 else { return Self.maxSize }
        let scale = min(Self.maxSize.width / CGFloat(width), Self.maxSize.height / CGFloat(height), 1)
        return CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }
}
