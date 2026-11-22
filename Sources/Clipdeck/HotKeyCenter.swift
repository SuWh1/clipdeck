import Carbon.HIToolbox
import ClipdeckCore

@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x434C_5044

    var onPress: (() -> Void)?
    private(set) var registered: KeyShortcut?

    private var hotKey: EventHotKeyRef?
    private var hotKeyID: UInt32 = 0
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            let handled = MainActor.assumeIsolated { center.handlePress(pressed) }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &eventType, context, &handler)
        if status != noErr {
            Log.app.error("Installing the shortcut handler failed with status \(status)")
        }
    }

    func register(_ shortcut: KeyShortcut) -> Bool {
        if shortcut == registered {
            return true
        }
        let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
        nextID += 1
        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &newHotKey
        )
        guard status == noErr, let newHotKey else {
            Log.app.error("Registering the shortcut failed with status \(status)")
            return false
        }
        unregister()
        hotKey = newHotKey
        hotKeyID = identifier.id
        registered = shortcut
        return true
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        registered = nil
    }

    private func handlePress(_ pressed: EventHotKeyID) -> Bool {
        guard pressed.signature == Self.signature, pressed.id == hotKeyID, registered != nil else { return false }
        onPress?()
        return true
    }
}
