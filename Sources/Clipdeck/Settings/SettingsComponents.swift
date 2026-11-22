import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    var note: String?
    var noteIsWarning = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.055)))
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(noteIsWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

struct PanelButtonStyle: ButtonStyle {
    var isDestructive = false
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var foreground: AnyShapeStyle {
        if isProminent { return AnyShapeStyle(.white) }
        return isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
    }

    private var background: AnyShapeStyle {
        if isProminent { return isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint) }
        return AnyShapeStyle(.primary.opacity(0.09))
    }
}
