//
//  StatusMenu.swift
//  XDRGamma
//

import Cocoa

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let controller: GammaController
    private let slider = NSSlider()
    private let toggleItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let thermalPrefItem = NSMenuItem()
    private let fullBrightnessItem = NSMenuItem()
    private let statusLineItem = NSMenuItem()
    private let thermalLineItem = NSMenuItem()

    init(controller: GammaController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

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

        // Intensity slider as a custom view inside a menu item.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))

        let label = NSTextField(labelWithString: "Intensity")
        label.font = .menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 22, width: 190, height: 16)
        container.addSubview(label)

        slider.minValue = 0
        slider.maxValue = 1
        slider.floatValue = controller.userBrightness
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.frame = NSRect(x: 14, y: 2, width: 192, height: 20)
        container.addSubview(slider)

        let sliderItem = NSMenuItem()
        sliderItem.view = container
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        fullBrightnessItem.title = "Only at Full Brightness"
        fullBrightnessItem.target = self
        fullBrightnessItem.action = #selector(fullBrightnessTapped)
        fullBrightnessItem.toolTip = "Leave the display stock until the slider reaches "
            + "the top, then hand over the extra range. Off blends the boost in across "
            + "the whole slider."
        menu.addItem(fullBrightnessItem)

        menu.addItem(.separator())

        loginItem.title = "Launch at Login"
        loginItem.target = self
        loginItem.action = #selector(loginItemTapped)
        menu.addItem(loginItem)

        thermalPrefItem.title = "Pause When Overheating"
        thermalPrefItem.target = self
        thermalPrefItem.action = #selector(thermalPrefTapped)
        menu.addItem(thermalPrefItem)

        let hideIconItem = NSMenuItem(
            title: "Hide Menu Bar Icon",
            action: #selector(hideIconTapped),
            keyEquivalent: ""
        )
        hideIconItem.target = self
        menu.addItem(hideIconItem)

        menu.addItem(.separator())

        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        thermalLineItem.isEnabled = false
        menu.addItem(thermalLineItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updateUI() {
        toggleItem.title = controller.isUserEnabled ? "Disable" : "Enable"

        loginItem.state = LoginItem.isEnabled ? .on : .off
        // .notFound means we are running outside an .app bundle.
        loginItem.isEnabled = LoginItem.status != .notFound
        loginItem.toolTip = "Launch at login: \(LoginItem.localizedStatus)"

        thermalPrefItem.state = Settings.shared.disableOnThermalPressure ? .on : .off

        fullBrightnessItem.state = Settings.shared.onlyAtFullBrightness ? .on : .off

        statusLineItem.title = controller.statusLine()
        thermalLineItem.title = controller.thermalLine()

        if let button = statusItem.button {
            let symbol: String
            if controller.isThermallySuspended {
                symbol = "thermometer.high"
            } else if controller.isActive {
                symbol = "sun.max.fill"
            } else {
                symbol = "sun.max"
            }
            button.image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: "XDR Gamma"
            )
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
    }

    @objc private func sliderChanged() {
        controller.setUserBrightness(slider.floatValue)
    }

    @objc private func fullBrightnessTapped() {
        Settings.shared.onlyAtFullBrightness.toggle()
        controller.boostCurveChanged()
        updateUI()
    }

    @objc private func thermalPrefTapped() {
        Settings.shared.disableOnThermalPressure.toggle()
        controller.thermalPreferenceChanged()
        updateUI()
    }

    @objc private func hideIconTapped() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = """
        The brightness boost keeps running, but there will be no way to \
        control it.

        To bring the icon back, launch XDRGamma again — double-click \
        XDRGamma.app or open it from Spotlight.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            hideIcon()
        }
    }

    @objc private func loginItemTapped() {
        let wantEnabled = !LoginItem.isEnabled

        if let error = LoginItem.setEnabled(wantEnabled) {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = error
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else if LoginItem.requiresUserApproval {
            let alert = NSAlert()
            alert.messageText = "Approval required"
            alert.informativeText = """
            Launch at login was turned off by hand. Allow XDRGamma under \
            General → Login Items & Extensions in System Settings.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                LoginItem.openSystemSettings()
            }
        }
        updateUI()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}
