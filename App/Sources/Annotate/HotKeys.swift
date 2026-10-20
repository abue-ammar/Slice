//
//  HotKeys.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts that work whichever app is in front. Carbon's hot keys need no Accessibility access, and the
/// key press goes to Slice alone, not on to the app being recorded.
@MainActor
final class HotKeys {
    struct Combo: Hashable {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
        }

        func matches(_ event: NSEvent) -> Bool {
            Int(event.keyCode) == keyCode && event.modifierFlags.intersection([.command, .option, .control, .shift]) == modifiers
        }

        var carbonModifiers: UInt32 {
            var m: UInt32 = 0
            if modifiers.contains(.command) { m |= UInt32(cmdKey) }
            if modifiers.contains(.option) { m |= UInt32(optionKey) }
            if modifiers.contains(.control) { m |= UInt32(controlKey) }
            if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
            return m
        }
    }

    static let shared = HotKeys()

    private var registered: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    /// Returns a token for `unregister`, or nil if another app already holds the combination.
    @discardableResult
    func register(_ combo: Combo, action: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.warning("Couldn't register a shortcut (\(status)); another app may be using it.")
            return nil
        }
        registered[id] = (ref, action)
        return id
    }

    func unregister(_ id: UInt32?) {
        guard let id, let entry = registered.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    private static let signature: OSType = 0x534C_4345 // "SLCE"

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let id = key.id
            MainActor.assumeIsolated { HotKeys.shared.registered[id]?.action() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
