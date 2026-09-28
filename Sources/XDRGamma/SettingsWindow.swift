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
    private var outsideClicks: Any?

    private let panel = RetroPanelView()
    private var boostCheck: RetroCheck!
    private var fullBrightnessCheck: RetroCheck!
    private var thermalCheck: RetroCheck!
    private var appPauseCheck: RetroCheck!
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

    // Closing on NSApplication.didResignActive was tried and removed: an
    // accessory app can lose active status a moment after activating it, and
    // the panel shut itself the instant it opened. The global click monitor
    // below dismisses on the case that actually matters — a click elsewhere —
    // without depending on focus at all.

    // MARK: - Presenting

    /// `anchor` is the status item's frame in screen coordinates; the panel
    /// hangs from it like a menu would.
    func show(anchor: NSRect?) {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        position(under: anchor)
        window?.makeKeyAndOrderFront(nil)
        sync()
        refresh?.invalidate()
        // The diagnostics line is live, so keep it moving while the panel is up.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer

        watchForClicksOutside()
    }

    func close() {
        refresh?.invalidate()
        refresh = nil
        if let outsideClicks {
            NSEvent.removeMonitor(outsideClicks)
            self.outsideClicks = nil
        }
        window?.orderOut(nil)
    }

    /// Dismiss on a click anywhere else, the way a menu does.
    ///
    /// This is a *global* monitor on purpose. Closing on `windowDidResignKey`
    /// looks equivalent and is not: clicking the status icon makes the panel
    /// resign key first, so the panel closed and the click that followed
    /// immediately reopened it — the icon appeared not to toggle at all. A
    /// global monitor never sees events in our own process, so the status icon
    /// is left to `iconClicked`, which toggles honestly. It also means an
    /// NSAlert raised from the panel no longer dismisses it.
    private func watchForClicksOutside() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        refresh?.invalidate()
        refresh = nil
    }

    var isVisible: Bool { window?.isVisible == true }

    /// True for a moment after the panel dismissed itself.
    ///
    /// Clicking the status icon makes the panel resign key *before* the click
    /// reaches the icon's action, so by then the panel has already closed and a
    /// naive action would reopen it — the icon would appear not to toggle at
    /// all, which is exactly the bug this exists to prevent. The action asks
    /// this instead of asking whether the window is visible.
    var justDismissed: Bool {
        guard let dismissedAt else { return false }
        return Date().timeIntervalSince(dismissedAt) < 0.35
    }

    private var dismissedAt: Date?

    /// A menu goes away when you click elsewhere, and losing key is the most
    /// reliable signal for that — the global monitor below does not see every
    /// case, so both are kept.
    func windowDidResignKey(_ notification: Notification) {
        dismissedAt = Date()
        close()
    }

    /// Hang the panel under the status item, nudged to stay on screen.
    private func position(under anchor: NSRect?) {
        guard let window else { return }
        guard let anchor,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
                ?? NSScreen.main else {
            window.center()
            return
        }
        let size = window.frame.size
        let gap: CGFloat = 6
        var x = anchor.midX - size.width / 2
        let visible = screen.visibleFrame
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        let y = min(anchor.minY, visible.maxY) - gap - size.height
        window.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
    }

    // MARK: - Building

    private func build() {
        let width: CGFloat = 460
        let height: CGFloat = 618
        let w = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.delegate = self

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        panel.title = "XDR Gamma"
        panel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(panel)

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 14
        body.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(body)

        // Blurb, centred like the reference.
        let blurb = Retro.label(
            "Lifts the SDR brightness ceiling of the built-in XDR panel "
            + "by holding it in HDR mode and scaling the transfer table "
            + "into the headroom that opens up.",
            size: 12, align: .center)
        blurb.preferredMaxLayoutWidth = width - 68
        body.addArrangedSubview(blurb)
        body.setCustomSpacing(20, after: blurb)

        boostCheck = RetroCheck(title: "Brightness boost",
                                detail: "Ceiling 1000 nits — the sustained rating") { [weak self] in
            self?.controller.toggle()
            self?.sync()
        }
        fullBrightnessCheck = RetroCheck(
            title: "Only at full brightness",
            detail: "Stock until the slider reaches the top") { [weak self] in
            Settings.shared.onlyAtFullBrightness.toggle()
            self?.controller.boostCurveChanged()
            self?.sync()
        }
        thermalCheck = RetroCheck(
            title: "Pause when overheating",
            detail: "Dropped while the system throttles") { [weak self] in
            Settings.shared.disableOnThermalPressure.toggle()
            self?.controller.thermalPreferenceChanged()
            self?.sync()
        }
        appPauseCheck = RetroCheck(
            title: "Pause for HDR apps",
            detail: "Photos, Preview, QuickTime Player clip otherwise") { [weak self] in
            Settings.shared.pauseForIncompatibleApps.toggle()
            self?.controller.incompatibleAppPreferenceChanged()
            self?.sync()
        }
        loginCheck = RetroCheck(title: "Launch at login",
                                detail: "Needs the .app bundle") { [weak self] in
            self?.toggleLoginItem()
        }

        for c in [boostCheck!, fullBrightnessCheck!, thermalCheck!, appPauseCheck!, loginCheck!] {
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

        let rule = Retro.label(String(repeating: "─", count: 38), size: 12, color: Retro.dim)
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

            body.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 34),
            body.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -34),
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
        appPauseCheck?.isOn = Settings.shared.pauseForIncompatibleApps

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
