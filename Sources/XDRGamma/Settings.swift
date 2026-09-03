//
//  Settings.swift
//  XDRGamma
//

import Foundation

@MainActor
final class Settings {

    static let shared = Settings()

    private enum Key {
        static let enabled = "enabled"
        static let userBrightness = "userBrightness"
        static let disableOnThermalPressure = "disableOnThermalPressure"
        static let hideStatusIcon = "hideStatusIcon"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.enabled: false,
            Key.userBrightness: 1.0,
            Key.disableOnThermalPressure: true,
            Key.hideStatusIcon: false
        ])
    }

    /// What the user asked for. Restored on launch.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var userBrightness: Float {
        get { defaults.float(forKey: Key.userBrightness) }
        set { defaults.set(newValue, forKey: Key.userBrightness) }
    }

    /// Drop the boost while the system reports thermal throttling.
    var disableOnThermalPressure: Bool {
        get { defaults.bool(forKey: Key.disableOnThermalPressure) }
        set { defaults.set(newValue, forKey: Key.disableOnThermalPressure) }
    }

    /// Hide the menu bar icon. Relaunching the app brings it back.
    var hideStatusIcon: Bool {
        get { defaults.bool(forKey: Key.hideStatusIcon) }
        set { defaults.set(newValue, forKey: Key.hideStatusIcon) }
    }
}
