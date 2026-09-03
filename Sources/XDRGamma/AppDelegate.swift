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
    private var menu: StatusMenu!
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = GammaController()
        menu = StatusMenu(controller: controller)

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
    /// menu bar icon back.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        menu.showIcon()
        return true
    }

    /// A modified gamma table outlives the process. Without these nets a crash
    /// would leave the screen blown out until reboot.
    private func installSafetyNets() {
        atexit(emergencyRestore)

        // Only the orderly signals are worth handling. A crash needs no net:
        // WindowServer drops the gamma table when the setting process dies —
        // measured on macOS 26.5 for SIGSEGV and for SIGKILL, which cannot be
        // caught anyway. Handling crash signals here would buy nothing and
        // cost a non-async-signal-safe WindowServer call on the crash path.
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
