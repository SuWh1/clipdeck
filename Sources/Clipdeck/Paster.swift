import AppKit
import Carbon.HIToolbox
import ClipdeckCore

enum PasteMode {
    case normal, plainText, copyOnly
}

@MainActor
enum Paster {
    enum Outcome: Equatable {
        case pasted, copied, needsPermission
        case failed(String)
    }

    private static let pasteDelay: Duration = .milliseconds(80)
    private static var hasAskedForAccessibility = false

    static func paste(itemID: Int64, store: HistoryStore, plainText: Bool, autoPaste: Bool, targetProcess: pid_t?) -> Outcome {
        do {
            guard let item = try store.item(id: itemID) else {
                return .failed("This item is no longer in your history.")
            }
            let imageData = try store.imageURL(for: item).map { try Data(contentsOf: $0) }
            guard PasteboardWriter.write(item, imageData: imageData, plainTextOnly: plainText, to: .general) else {
                return .failed("This item could not be copied. Its image may have been deleted.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        guard autoPaste else { return .copied }
        guard AXIsProcessTrusted() else {
            if !hasAskedForAccessibility {
                hasAskedForAccessibility = true
                requestAccessibility()
            }
            return .needsPermission
        }
        Task { @MainActor in
            try? await Task.sleep(for: pasteDelay)
            guard targetProcess == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcess else {
                Log.app.notice("Skipped pasting because a different app came to the front")
                return
            }
            postCommandV()
        }
        return .pasted
    }

    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static func postCommandV() {
        let keyCode = CGKeyCode(KeyboardLayout.keyCode(for: "v") ?? UInt32(kVK_ANSI_V))
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
