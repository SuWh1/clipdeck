import AppKit
import ClipdeckCore
import SwiftUI

extension PanelTheme {
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(red: 0.96, green: 0.33, blue: 0.64)
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .green: Color(nsColor: .systemGreen)
        case .graphite: Color(nsColor: .systemGray)
        }
    }
}

struct AppearanceSection: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        SettingsSection(title: "Appearance") {
            HStack(spacing: 8) {
                ForEach(PanelAppearance.allCases) { option in
                    AppearanceTile(appearance: option, isSelected: settings.appearance == option) {
                        settings.appearance = option
                    }
                }
            }
            .padding(12)
            RowDivider()
            SettingsRow(title: "Accent") {
                AccentPicker(selection: $settings.theme)
            }
            RowDivider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Transparency").font(.system(size: 13))
                HStack(spacing: 10) {
                    Text("Solid").fixedSize()
                    Slider(value: $settings.glass, in: 0...1) { Text("Transparency") }
                        .labelsHidden()
                        .controlSize(.small)
                    Text("Glass").fixedSize()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct AppearanceTile: View {
    let appearance: PanelAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
                    )
                Text(appearance.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch appearance {
        case .light:
            MiniPanel(isDark: false)
        case .dark:
            MiniPanel(isDark: true)
        case .system:
            MiniPanel(isDark: false)
                .overlay(MiniPanel(isDark: true).mask(HStack(spacing: 0) { Color.clear; Color.black }))
        }
    }
}

private struct MiniPanel: View {
    let isDark: Bool

    var body: some View {
        let ink = isDark ? Color.white : Color.black
        ZStack(alignment: .topLeading) {
            isDark ? Color(white: 0.17) : Color(white: 0.96)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.tint).frame(width: 18, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.22)).frame(height: 6)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.12)).frame(width: 34, height: 6)
            }
            .padding(8)
        }
    }
}

private struct AccentPicker: View {
    @Binding var selection: PanelTheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(PanelTheme.allCases) { theme in
                let isSelected = theme == selection
                Button {
                    selection = theme
                } label: {
                    swatch(theme)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                        .overlay {
                            if isSelected { Circle().fill(.white).frame(width: 6, height: 6) }
                        }
                        .padding(2.5)
                        .overlay(Circle().strokeBorder(isSelected ? AnyShapeStyle(.primary.opacity(0.35)) : AnyShapeStyle(.clear), lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.title)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func swatch(_ theme: PanelTheme) -> some View {
        if let color = theme.color {
            Circle().fill(color)
        } else {
            Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
        }
    }
}
