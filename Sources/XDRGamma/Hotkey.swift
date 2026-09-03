//
//  Hotkey.swift
//  XDRGamma
//
//  A system-wide shortcut for toggling the boost.
//
//  The boost clips HDR content — that is inherent to the gamma technique and
//  cannot be detected or handed over automatically, because macOS reports one
//  headroom value for the whole display and never tells an app that someone
//  else needs it. So the honest mitigation is a fast manual switch: hit the
//  key before a film, hit it again after, without hunting through a menu.
//
//  Carbon's RegisterEventHotKey is used rather than an NSEvent global monitor
//  on purpose: it needs no Accessibility permission and it fires even when the
//  app is an accessory with no windows.
//

import Cocoa
import Carbon.HIToolbox
import os

private let log = Logger(subsystem: "app.xdrgamma", category: "Hotkey")

@MainActor
final class GlobalHotkey {

    /// ⌃⌥⌘B — deliberately awkward enough that nothing else claims it.
    static let keyCode = UInt32(kVK_ANSI_B)
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let displayName = "⌃⌥⌘B"

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Set while a hotkey is installed, so the C callback can reach it.
    private static var current: GlobalHotkey?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var isRegistered: Bool { ref != nil }

    /// Returns false when the combination is already taken by another app.
    @discardableResult
    func register() -> Bool {
        guard ref == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == GlobalHotkey.signature else { return noErr }
            MainActor.assumeIsolated { GlobalHotkey.current?.action() }
            return noErr
        }, 1, &eventType, nil, &handler)

        guard installed == noErr else {
            log.error("Could not install the hotkey event handler: \(installed)")
            return false
        }

        let id = EventHotKeyID(signature: GlobalHotkey.signature, id: 1)
        let status = RegisterEventHotKey(GlobalHotkey.keyCode, GlobalHotkey.modifiers,
                                         id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else {
            log.error("Could not register \(GlobalHotkey.displayName): \(status)")
            ref = nil
            unwind()
            return false
        }

        GlobalHotkey.current = self
        log.info("Registered \(GlobalHotkey.displayName)")
        return true
    }

    func unregister() {
        guard let ref else { return }
        UnregisterEventHotKey(ref)
        self.ref = nil
        if GlobalHotkey.current === self { GlobalHotkey.current = nil }
        unwind()
        log.info("Released \(GlobalHotkey.displayName)")
    }

    private func unwind() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// Four-char code identifying our hotkey among any others in the process.
    private static let signature: OSType = {
        let chars = Array("XDRG".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()
}
