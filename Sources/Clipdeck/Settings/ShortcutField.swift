import AppKit
import Carbon.HIToolbox
import ClipdeckCore
import SwiftUI

struct ShortcutField: View {
    let shortcut: KeyShortcut
    let onRecord: (KeyShortcut) -> Void
    let onRecordingChange: (Bool) -> Void
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            if shortcut != .standard && !isRecording {
                Button { onRecord(.standard) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset to \(KeyShortcut.standard.displayString)")
                .accessibilityLabel("Reset shortcut")
            }
            Button(action: toggleRecording) {
                Text(isRecording ? hint ?? "Type keys…" : shortcut.displayString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .frame(minWidth: 80)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(shortcut.displayString), click to change")
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        hint = nil
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        hint = nil
        onRecordingChange(false)
    }

    private func record(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            stopRecording()
            return
        }
        let candidate = KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            hint = "Add ⌃ or ⌥, or ⌘⇧"
            return
        }
        stopRecording()
        onRecord(candidate)
    }
}
