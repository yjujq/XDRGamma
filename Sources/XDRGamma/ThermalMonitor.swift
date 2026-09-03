//
//  ThermalMonitor.swift
//  XDRGamma
//
//  A raised backlight ceiling heats the panel. Once the system is already
//  throttling for temperature, adding heat is pointless: macOS will cut
//  brightness anyway, and it will do so abruptly.
//

import Foundation

@MainActor
final class ThermalMonitor {

    private(set) var state: ProcessInfo.ThermalState

    var onChange: (() -> Void)?

    /// .serious and .critical mean the system is actively throttling.
    /// .fair is left alone — that is ordinary heat under load.
    var isUnderPressure: Bool {
        state == .serious || state == .critical
    }

    var localizedState: String {
        switch state {
        case .nominal:  return "normal"
        case .fair:     return "warm"
        case .serious:  return "hot"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    init() {
        state = ProcessInfo.processInfo.thermalState

        // The notification arrives on an arbitrary thread — force it to main.
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let newState = ProcessInfo.processInfo.thermalState
        guard newState != state else { return }
        state = newState
        onChange?()
    }
}
