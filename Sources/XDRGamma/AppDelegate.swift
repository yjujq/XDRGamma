//
//  AppDelegate.swift
//  XDRGamma
//

import Cocoa

/// Global hook for emergency restore from a C context (atexit / signal).
private let emergencyRestore: @convention(c) () -> Void = {
    CGDisplayRestoreColorSyncSettings()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: GammaController!
    private var statusItem: StatusItemController!
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = GammaController()
        statusItem = StatusItemController(controller: controller)

        installSafetyNets()

        if controller.compatibleScreens.isEmpty {
            warnNoCompatibleDisplay()
        }

        // Bring back whatever state the last run left behind.
        controller.restoreSavedState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAndStop()
    }

    /// Relaunching the already-running app is the only way to bring a hidden
    /// menu bar icon back, and the natural thing to expect from opening an app
    /// that is already running is that it shows you something.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        statusItem.showIcon()
        statusItem.showSettings()
        return true
    }

    /// A modified gamma table outlives the process. Without these nets a crash
    /// would leave the screen blown out until reboot.
    private func installSafetyNets() {
        atexit(emergencyRestore)

        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    self.controller.restoreAndStop()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func warnNoCompatibleDisplay() {
        let alert = NSAlert()
        alert.messageText = "No compatible display found"
        alert.informativeText = """
        This needs a display with EDR brightness headroom: a built-in Liquid \
        Retina XDR panel (14"/16" MacBook Pro on Apple Silicon) or a Pro \
        Display XDR.

        The app will stay in the menu bar, but the boost will be unavailable.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
}
