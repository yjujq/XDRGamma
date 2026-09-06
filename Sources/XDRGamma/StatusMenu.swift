//
//  StatusMenu.swift
//  XDRGamma
//
//  The menu keeps only what a menu is genuinely good at: the state of the
//  boost at a glance, one click to flip it, and a way into the settings panel.
//  Everything else lives in SettingsWindow.
//

import Cocoa

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let controller: GammaController
    private let settings: SettingsWindowController
    private let toggleItem = NSMenuItem()
    private let statusLineItem = NSMenuItem()

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

        buildMenu()
        updateUI()

        // The icon may have been hidden in a previous run.
        statusItem.isVisible = !Settings.shared.hideStatusIcon
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem.title = "Enable"
        toggleItem.target = self
        toggleItem.action = #selector(toggleTapped)
        toggleItem.keyEquivalent = "b"
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(settingsTapped),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updateUI() {
        toggleItem.title = controller.isUserEnabled ? "Disable" : "Enable"
        statusLineItem.title = controller.statusLine()

        if let button = statusItem.button {
            let symbol: String
            if controller.isThermallySuspended {
                symbol = "thermometer.high"
            } else if controller.isActive {
                symbol = "sun.max.fill"
            } else {
                symbol = "sun.max"
            }
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "XDR Gamma")
            button.image?.isTemplate = true
            button.appearsDisabled = !controller.isActive
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateUI()
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
        updateUI()
    }

    @objc private func toggleTapped() {
        controller.toggle()
        updateUI()
    }

    func showSettings() {
        settings.show()
    }

    @objc private func settingsTapped() {
        settings.show()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}
