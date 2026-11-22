import ClipdeckCore
import SwiftUI

struct ClipRowActions {
    let paste: () -> Void
    let pastePlain: () -> Void
    let copy: () -> Void
    let togglePin: () -> Void
    let delete: () -> Void
}

struct ClipRowView: View {
    let item: ClipItem
    let shortcutNumber: Int?
    let isSelected: Bool
    let imageURL: URL?
    let actions: ClipRowActions
    @State private var isHovered = false

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ClipPreview(item: item, imageURL: imageURL)
            meta
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(background))
        .overlay(shape.strokeBorder(isSelected ? AnyShapeStyle(TintShapeStyle().opacity(0.55)) : AnyShapeStyle(.clear), lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: actions.paste)
        .contextMenu {
            Button("Paste", action: actions.paste)
            if item.kind == .text || item.kind == .link {
                Button("Paste as Plain Text", action: actions.pastePlain)
            }
            Button("Copy", action: actions.copy)
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin", action: actions.togglePin)
            Divider()
            Button("Delete", role: .destructive, action: actions.delete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Paste", actions.paste)
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(TintShapeStyle().opacity(0.18)) }
        return AnyShapeStyle(.primary.opacity(isHovered ? 0.09 : 0.045))
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if let icon = AppIcons.icon(forBundleID: item.source?.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            }
            Text(item.source?.name ?? kindName)
                .lineLimit(1)
            Text("·")
            Text(RelativeTime.string(for: item.lastCopiedAt))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let detail {
                Text(detail).lineLimit(1)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Pinned")
            }
            if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var kindName: String {
        switch item.kind {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    private var detail: String? {
        switch item.kind {
        case .image: "\(item.imageWidth) × \(item.imageHeight)"
        case .text where item.characterCount > 200: "\(item.characterCount.formatted()) chars"
        case .file where item.filePaths.count > 1: "\(item.filePaths.count) files"
        default: nil
        }
    }
}

@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(for date: Date, now: Date = Date()) -> String {
        now.timeIntervalSince(date) < 60 ? "Just now" : formatter.localizedString(for: date, relativeTo: now)
    }
}
