//
//  LoginItem.swift
//  XDRGamma
//

import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "app.xdrgamma", category: "LoginItem")

@MainActor
enum LoginItem {

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// The user turned the login item off by hand — registering again from
    /// inside the app will not help.
    static var requiresUserApproval: Bool {
        status == .requiresApproval
    }

    static var localizedStatus: String {
        switch status {
        case .enabled:          return "on"
        case .notRegistered:    return "off"
        case .notFound:         return "unavailable (launch from the .app bundle)"
        case .requiresApproval: return "needs approval in System Settings"
        @unknown default:       return "unknown"
        }
    }

    /// Returns an error message when the toggle fails, nil on success.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard status != .notRegistered else { return nil }
                try SMAppService.mainApp.unregister()
            }
            log.info("Login item toggled: \(enabled)")
            return nil
        } catch {
            log.error("Failed to toggle login item: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
