//
//  IncompatibleAppMonitor.swift
//  XDRGamma
//
//  The gamma technique claims the display's entire EDR headroom for SDR
//  content, which is the same headroom actual HDR content needs for its own
//  highlights (see README, "HDR content"). There is no way to ask macOS
//  whether the frontmost app is showing any right now — headroom is reported
//  once for the whole display, not per app — so this watches for a short
//  list of apps that routinely show full-res HDR photos or video and treats
//  them as reason enough to drop the boost on their own.
//
//  This is a heuristic, not a detector: it does not see Quick Look panels
//  (owned by Finder) or HDR images inline in Safari or Messages. It catches
//  the common case — opening Photos or Preview on a shot that turns out to
//  be HDR — without watching every app's windows.
//

import Cocoa

@MainActor
final class IncompatibleAppMonitor {

    /// Apps that commonly display full-res HDR photos or video.
    private static let incompatibleBundleIds: Set<String> = [
        "com.apple.Photos",
        "com.apple.Preview",
        "com.apple.QuickTimePlayerX",
    ]

    private(set) var frontmostBundleId: String?

    var onChange: (() -> Void)?

    var isFrontmostIncompatible: Bool {
        guard let frontmostBundleId else { return false }
        return Self.incompatibleBundleIds.contains(frontmostBundleId)
    }

    /// The name to show in diagnostics while paused for this reason.
    var frontmostLocalizedName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    init() {
        frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.refresh(notification)
            }
        }
    }

    private func refresh(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let newId = app?.bundleIdentifier
        guard newId != frontmostBundleId else { return }
        let wasIncompatible = isFrontmostIncompatible
        frontmostBundleId = newId
        if isFrontmostIncompatible != wasIncompatible {
            onChange?()
        }
    }
}
