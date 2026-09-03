//
//  main.swift
//  XDRGamma
//

import Cocoa

// NSApplication.delegate is a weak reference, so hold the delegate globally.
var appDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    appDelegate = delegate
    app.delegate = delegate
    // Menu bar only: no Dock icon, no window.
    app.setActivationPolicy(.accessory)
    app.run()
}
