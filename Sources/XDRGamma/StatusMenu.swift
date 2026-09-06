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
    /// Held rather than attached: attaching a menu to the status item would
    /// make every click open it, and the left click belongs to the panel.
    private let menu = NSMenu()

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

        // The icon used to refresh only when the menu was opened, which was
        // enough while every click opened it. Now that a click opens the panel
        // instead, the icon has to follow the controller directly — otherwise a
        // thermal pause would never show its thermometer.
        controller.onStateChange = { [weak self] in
            MainActor.assumeIsolated { self?.updateUI() }
        }

        buildMenu()
        updateUI()

        // The icon may have been hidden in a previous run.
        statusItem.isVisible = !Settings.shared.hideStatusIcon
    }

    private func buildMenu() {
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

        // Left click opens the panel; the menu stays available on right click
        // for a toggle without opening anything.
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func iconClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu { popUpMenu() } else { showSettings() }
    }

    /// Attach, click, detach — the only way to pop a status item menu on demand
    /// without leaving it attached and losing the left click to it.
    private func popUpMenu() {
        updateUI()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
        settings.show(anchor: statusItem.button?.window?.frame)
    }

    @objc private func settingsTapped() {
        showSettings()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}
