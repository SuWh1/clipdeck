import ClipdeckCore
import SwiftUI

struct HistoryView: View {
    @Bindable var model: HistoryModel
    let actions: PanelActions
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            FilterBar(selection: $model.filter)
                .padding(.bottom, 8)
            if let message = model.errorMessage {
                ErrorBanner(message: message)
            }
            content
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isSearchFocused = true }
        .onChange(of: model.showCount) { isSearchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.search)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.07)))

            IconButton(systemName: "gearshape", label: "Settings", action: actions.openSettings)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            EmptyHistoryView(search: model.search, filter: model.filter, hasAnyItems: model.totalCount > 0)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ClipRowView(
                                item: item,
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                isSelected: item.id == model.selectedID,
                                imageURL: model.imageURL(for: item),
                                actions: rowActions(for: item)
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private var footer: some View {
        PanelFooter {
            Text(model.totalCount == 1 ? "1 item" : "\(model.totalCount) items")
            Spacer()
            KeyHint(keys: "↩", label: "Paste")
            KeyHint(keys: "⇧↩", label: "Plain")
            KeyHint(keys: "⌘P", label: "Pin")
        }
    }

    private func rowActions(for item: ClipItem) -> ClipRowActions {
        ClipRowActions(
            paste: { actions.paste(item, .normal) },
            pastePlain: { actions.paste(item, .plainText) },
            copy: { actions.paste(item, .copyOnly) },
            togglePin: { model.togglePin(item) },
            delete: { model.delete(item) }
        )
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys).fontWeight(.medium).foregroundStyle(.primary.opacity(0.7))
            Text(label)
        }
    }
}

struct PanelFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .overlay(alignment: .top) {
                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            }
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.12)))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

private struct EmptyHistoryView: View {
    let search: String
    let filter: HistoryFilter
    let hasAnyItems: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "list.bullet.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if !search.isEmpty { return "No matches" }
        if !hasAnyItems { return "Nothing copied yet" }
        return filter == .pinned ? "No pinned items" : "No \(filter.title.lowercased()) yet"
    }

    private var message: String {
        if !search.isEmpty { return "Nothing in your history matches “\(search)”." }
        if !hasAnyItems { return "Copy text, links, images or files and they show up here." }
        return filter == .pinned ? "Press ⌘P on an item to keep it here for good." : "Press Tab to switch filters."
    }
}
