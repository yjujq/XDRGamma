//
//  SettingsWindow.swift
//  XDRGamma
//
//  Every setting the app has, in one panel, drawn in the terminal style from
//  RetroKit. The menu bar keeps only what a menu is good at: a quick toggle and
//  a way in here.
//

import Cocoa

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let controller: GammaController
    private var window: NSWindow?
    private var refresh: Timer?

    private let panel = RetroPanelView()
    private var boostCheck: RetroCheck!
    private var fullBrightnessCheck: RetroCheck!
    private var thermalCheck: RetroCheck!
    private var loginCheck: RetroCheck!
    private var intensity: RetroBar!
    private var intensityCaption: NSTextField!
    private var statusField: NSTextField!
    private var thermalField: NSTextField!
    private var toggleButton: RetroButton!

    init(controller: GammaController) {
        self.controller = controller
        super.init()
    }

    // MARK: - Presenting

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        sync()
        refresh?.invalidate()
        // The diagnostics line is live, so keep it moving while the panel is up.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer
    }

    func close() {
        refresh?.invalidate()
        refresh = nil
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        refresh?.invalidate()
        refresh = nil
    }

    // MARK: - Building

    private func build() {
        let width: CGFloat = 640
        let w = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 596),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.delegate = self

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 596))

        panel.title = "XDR Gamma"
        panel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(panel)

        let close = RetroClose()
        close.translatesAutoresizingMaskIntoConstraints = false
        close.onClick = { [weak self] in self?.close() }
        root.addSubview(close)

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 14
        body.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(body)

        // Blurb, centred like the reference.
        let blurb = Retro.label(
            "This lifts the SDR brightness limit of the built-in XDR panel by "
            + "holding it in HDR mode and scaling the display transfer table into "
            + "the headroom that opens up. Public APIs only.",
            size: 12.5, align: .center)
        blurb.preferredMaxLayoutWidth = width - 120
        body.addArrangedSubview(blurb)
        body.setCustomSpacing(20, after: blurb)

        boostCheck = RetroCheck(title: "Brightness boost",
                                detail: "Ceiling 1000 nits, the panel's sustained rating") { [weak self] in
            self?.controller.toggle()
            self?.sync()
        }
        fullBrightnessCheck = RetroCheck(
            title: "Only at full brightness",
            detail: "Stay stock until the slider reaches the top, then hand over the range") { [weak self] in
            Settings.shared.onlyAtFullBrightness.toggle()
            self?.controller.boostCurveChanged()
            self?.sync()
        }
        thermalCheck = RetroCheck(
            title: "Pause when overheating",
            detail: "Drop the boost while the system reports throttling") { [weak self] in
            Settings.shared.disableOnThermalPressure.toggle()
            self?.controller.thermalPreferenceChanged()
            self?.sync()
        }
        loginCheck = RetroCheck(title: "Launch at login",
                                detail: "Requires running from the .app bundle") { [weak self] in
            self?.toggleLoginItem()
        }

        for c in [boostCheck!, fullBrightnessCheck!, thermalCheck!, loginCheck!] {
            c.translatesAutoresizingMaskIntoConstraints = false
            body.addArrangedSubview(c)
            c.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        body.setCustomSpacing(22, after: loginCheck)

        intensityCaption = Retro.label("Intensity", size: 14)
        body.addArrangedSubview(intensityCaption)

        intensity = RetroBar()
        intensity.translatesAutoresizingMaskIntoConstraints = false
        intensity.onChange = { [weak self] v in
            self?.controller.setUserBrightness(v)
            self?.sync()
        }
        body.addArrangedSubview(intensity)
        intensity.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        body.setCustomSpacing(24, after: intensity)

        let rule = Retro.label(String(repeating: "─", count: 46), size: 12, color: Retro.dim)
        body.addArrangedSubview(rule)

        statusField = Retro.label("", size: 12.5)
        thermalField = Retro.label("", size: 12.5, color: Retro.dim)
        body.addArrangedSubview(statusField)
        body.addArrangedSubview(thermalField)

        // Buttons
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 14
        buttons.translatesAutoresizingMaskIntoConstraints = false

        toggleButton = RetroButton(title: "Enable", kind: .primary) { [weak self] in
            self?.controller.toggle()
            self?.sync()
        }
        let hideButton = RetroButton(title: "Hide Icon") { [weak self] in self?.hideIcon() }
        let quitButton = RetroButton(title: "Quit") { NSApp.terminate(nil) }
        for b in [toggleButton!, hideButton, quitButton] {
            b.translatesAutoresizingMaskIntoConstraints = false
            buttons.addArrangedSubview(b)
        }
        panel.addSubview(buttons)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panel.topAnchor.constraint(equalTo: root.topAnchor),
            panel.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            close.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 34),
            close.heightAnchor.constraint(equalToConstant: 34),

            body.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 60),
            body.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -60),
            body.topAnchor.constraint(equalTo: panel.topAnchor, constant: 54),

            buttons.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -42),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: body.bottomAnchor, constant: 24)
        ])

        w.contentView = root
        window = w
    }

    // MARK: - State

    private func sync() {
        boostCheck?.isOn = controller.isUserEnabled
        fullBrightnessCheck?.isOn = Settings.shared.onlyAtFullBrightness
        thermalCheck?.isOn = Settings.shared.disableOnThermalPressure

        loginCheck?.isOn = LoginItem.isEnabled
        loginCheck?.isEnabled = LoginItem.status != .notFound
        loginCheck?.detail = "Launch at login: \(LoginItem.localizedStatus)"

        intensity?.value = controller.userBrightness
        toggleButton?.title = controller.isUserEnabled ? "Disable" : "Enable"

        statusField?.stringValue = controller.statusLine()
        thermalField?.stringValue = controller.thermalLine()
    }

    // MARK: - Actions with consequences

    private func toggleLoginItem() {
        let want = !LoginItem.isEnabled
        if let error = LoginItem.setEnabled(want) {
            alert(title: "Could not change the login item", body: error, style: .warning)
        } else if LoginItem.requiresUserApproval {
            let a = NSAlert()
            a.messageText = "Approval required"
            a.informativeText = """
            Launch at login was turned off by hand. Allow XDRGamma under \
            General → Login Items & Extensions in System Settings.
            """
            a.alertStyle = .informational
            a.addButton(withTitle: "Open Settings")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { LoginItem.openSystemSettings() }
        }
        sync()
    }

    private func hideIcon() {
        let a = NSAlert()
        a.messageText = "Hide the menu bar icon?"
        a.informativeText = """
        The brightness boost keeps running, but there will be no way to control \
        it. To bring the icon back, launch XDRGamma again — double-click \
        XDRGamma.app or open it from Spotlight.
        """
        a.alertStyle = .informational
        a.addButton(withTitle: "Hide")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        NotificationCenter.default.post(name: .xdrHideStatusIcon, object: nil)
        close()
    }

    private func alert(title: String, body: String, style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.alertStyle = style
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}

/// A borderless window refuses to become key by default, which would leave the
/// panel unable to take keyboard focus or close on Escape.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

extension Notification.Name {
    /// Posted by the settings panel; the status item owns the icon, not us.
    static let xdrHideStatusIcon = Notification.Name("app.xdrgamma.hideStatusIcon")
}
