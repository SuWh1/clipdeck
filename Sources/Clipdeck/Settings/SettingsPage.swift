import AppKit
import ClipdeckCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsPage: View {
    @Bindable var settings: SettingsModel
    let actions: PanelActions
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    shortcutSection
                    generalSection
                    IgnoredAppsSection(settings: settings, actions: actions)
                    historySection
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.automatic)
            PanelFooter {
                Text("Clipdeck \(AppEnvironment.version)")
                Spacer()
                KeyHint(keys: "Esc", label: "Back")
            }
        }
        .onAppear(perform: settings.refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            settings.refreshStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "chevron.left", label: "Back to history", action: actions.showHistory)
            Text("Settings").font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var shortcutSection: some View {
        SettingsSection(
            title: "Shortcut",
            note: settings.shortcutError ?? "Press it in any app to open your history.",
            noteIsWarning: settings.shortcutError != nil
        ) {
            SettingsRow(title: "Open history") {
                ShortcutField(
                    shortcut: settings.shortcut,
                    onRecord: settings.applyShortcut,
                    onRecordingChange: settings.setRecordingShortcut
                )
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "General", note: settings.launchAtLoginMessage, noteIsWarning: true) {
            SettingsToggle(
                title: "Open at login",
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) })
            )
            RowDivider()
            SettingsToggle(title: "Paste into the active app", isOn: $settings.pasteDirectly)
            if settings.pasteDirectly && !settings.accessibilityTrusted {
                AccessibilityNotice(action: settings.openAccessibilitySettings)
            }
            RowDivider()
            SettingsRow(title: "Keep history for") { retentionMenu }
            RowDivider()
            SettingsToggle(title: "Pause recording", isOn: $settings.isPaused)
            RowDivider()
            SettingsRow(title: "Panel position") {
                if settings.hasCustomPanelPosition {
                    Button("Move to Top Right", action: settings.resetPanelPosition)
                        .buttonStyle(PanelButtonStyle())
                } else {
                    Text("Top right").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var retentionMenu: some View {
        Menu {
            ForEach(RetentionOption.allCases) { option in
                Button {
                    settings.retention = option
                } label: {
                    if option == settings.retention {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(settings.retention.title)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.09)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var historySection: some View {
        SettingsSection(
            title: "History",
            note: "Up to \(RetentionOption.maxItems.formatted()) items are kept. Pinned items are never removed."
        ) {
            SettingsRow(title: "Import from PasteNow") {
                if settings.importStatus == .running {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Choose File…", action: chooseDatabase).buttonStyle(PanelButtonStyle())
                }
            }
            if let message = importMessage {
                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundStyle(message.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            RowDivider()
            if isConfirmingClear {
                HStack(spacing: 8) {
                    Text("Delete everything except pinned items?")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Cancel") { isConfirmingClear = false }.buttonStyle(PanelButtonStyle())
                    Button("Clear") {
                        settings.clearHistory()
                        isConfirmingClear = false
                    }
                    .buttonStyle(PanelButtonStyle(isDestructive: true, isProminent: true))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            } else {
                SettingsRow(title: "Clear history") {
                    Button("Clear…") { isConfirmingClear = true }
                        .buttonStyle(PanelButtonStyle(isDestructive: true))
                }
            }
        }
    }

    private var importMessage: (text: String, isError: Bool)? {
        switch settings.importStatus {
        case .finished(let text): (text, false)
        case .failed(let text): (text, true)
        case .idle, .running: nil
        }
    }

    private func chooseDatabase() {
        actions.runDetached {
            let panel = NSOpenPanel()
            let defaultURL = PasteNowImporter.defaultDatabaseURL
            panel.directoryURL = FileManager.default.fileExists(atPath: defaultURL.path)
                ? defaultURL.deletingLastPathComponent()
                : FileManager.default.homeDirectoryForCurrentUser
            panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
            panel.message = "Choose PasteNow.sqlite"
            panel.prompt = "Import"
            if panel.runModal() == .OK, let url = panel.url {
                settings.importPasteNow(from: url)
            }
        }
    }
}

private struct AccessibilityNotice: View {
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs Accessibility access").font(.system(size: 12, weight: .medium))
                Text("Until you allow it, Clipdeck copies the item and you press ⌘V.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Allow…", action: action).buttonStyle(PanelButtonStyle(isProminent: true))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct IgnoredAppsSection: View {
    let settings: SettingsModel
    let actions: PanelActions

    var body: some View {
        SettingsSection(
            title: "Ignored apps",
            note: "Copies made in these apps are never saved. Password managers that mark copies as private are always skipped."
        ) {
            ForEach(installedApps, id: \.bundleID) { app in
                HStack(spacing: 10) {
                    if let icon = AppIcons.icon(forBundleID: app.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(app.name).font(.system(size: 13))
                    Spacer()
                    Button {
                        settings.removeIgnoredApp(app.bundleID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop ignoring \(app.name)")
                    .accessibilityLabel("Stop ignoring \(app.name)")
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                RowDivider()
            }
            Button(action: chooseApp) {
                Label("Add App…", systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var installedApps: [(bundleID: String, name: String)] {
        settings.ignoredBundleIDs.compactMap { id in AppNames.localizedName(for: id).map { (id, $0) } }
    }

    private func chooseApp() {
        actions.runDetached {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.prompt = "Ignore"
            if panel.runModal() == .OK, let url = panel.url {
                settings.addIgnoredApp(at: url)
            }
        }
    }
}
