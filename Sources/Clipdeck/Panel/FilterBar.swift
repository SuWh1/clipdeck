import ClipdeckCore
import SwiftUI

struct FilterBar: View {
    @Binding var selection: HistoryFilter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips.padding(.horizontal, 12)
            ScrollView(.horizontal) {
                chips.padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(HistoryFilter.allCases) { filter in
                FilterChip(title: filter.title, isSelected: filter == selection) {
                    selection = filter
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.8)))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint) }
        return AnyShapeStyle(.primary.opacity(isHovered ? 0.12 : 0.06))
    }
}
