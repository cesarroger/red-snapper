import Carbon.HIToolbox
import SnapCore

/// Registers system-wide hotkeys with the Carbon Event Manager (`RegisterEventHotKey`),
/// which needs no special permission and swallows the keystroke so the focused app never sees it.
final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, target: HotKeyTarget)] = [:]
    private let onTrigger: (HotKeyTarget) -> Void

    /// Targets whose combo could not be registered (usually taken by another app or the system).
    private(set) var failed: Set<HotKeyTarget> = []

    private static let signature: OSType = 0x5244_534E // 'RDSN'

    init(onTrigger: @escaping (HotKeyTarget) -> Void) {
        self.onTrigger = onTrigger
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Replaces all registrations.
    func register(_ hotKeys: [HotKeyTarget: KeyCombo]) {
        unregisterAll()
        failed = []
        var nextID: UInt32 = 1
        for (target, combo) in hotKeys {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: nextID),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[nextID] = (ref, target)
            } else {
                failed.insert(target)
                NSLog("RED SNAPPER: could not register \(combo.displayString) for \(target) (\(status))")
            }
            nextID += 1
        }
    }

    func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    // MARK: - Carbon plumbing

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            guard let target = manager.registered[hotKeyID.id]?.target else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { manager.onTrigger(target) }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
