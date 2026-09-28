//
//  StatusItem.swift
//  XDRGamma
//
//  The menu bar icon: it shows the state of the boost and opens the settings
//  panel. There is deliberately no menu behind it — the panel already holds
//  every control a menu would have offered, and a second copy of them is just
//  another surface to keep in sync.
//

import Cocoa

@MainActor
final class StatusItemController: NSObject {

    private let statusItem: NSStatusItem
    private let controller: GammaController
    private let settings: SettingsWindowController

    init(controller: GammaController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settings = SettingsWindowController(controller: controller)
        super.init()

        // The panel asks for this rather than reaching into the status item.
        NotificationCenter.default.addObserver(
            forName: .xdrHideStatusIcon, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideIcon() }
        }

        // The icon follows the controller directly. It used to refresh as a
        // side effect of the menu opening, which stopped being enough once the
        // menu went away — a thermal pause would never show its thermometer.
        controller.onStateChange = { [weak self] in
            MainActor.assumeIsolated { self?.updateIcon() }
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked)
            // Right and control clicks land here too, so they open the panel
            // rather than falling through to nothing.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon()

        // The icon may have been hidden in a previous run.
        statusItem.isVisible = !Settings.shared.hideStatusIcon
    }

    @objc private func iconClicked() {
        if settings.isVisible || settings.justDismissed {
            // Either it is still up, or this very click closed it by taking key
            // away — both mean the click is a dismissal, not a request to open.
            settings.close()
        } else {
            showSettings()
        }
    }

    func showSettings() {
        settings.show(anchor: statusItem.button?.window?.frame)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if controller.isThermallySuspended {
            symbol = "thermometer.high"
        } else if controller.isAppSuspended {
            symbol = "photo"
        } else if controller.isActive {
            symbol = "sun.max.fill"
        } else {
            symbol = "sun.max"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "XDR Gamma")
        button.image?.isTemplate = true
        button.appearsDisabled = !controller.isActive
    }

    /// Hides the icon. The boost keeps running.
    func hideIcon() {
        Settings.shared.hideStatusIcon = true
        statusItem.isVisible = false
    }

    /// The icon comes back when the app is launched again.
    func showIcon() {
        Settings.shared.hideStatusIcon = false
        statusItem.isVisible = true
        updateIcon()
    }
}
