//
//  GammaController.swift
//  XDRGamma
//
//  The flow: put the panel into HDR mode with the trigger, wait for real
//  headroom, then scale the display's transfer table and hold it there.
//
//  What the user asked for (isUserEnabled) is kept separate from what is
//  actually running (isActive): the boost can be dropped temporarily by
//  thermal throttling, and must come back on its own once things cool down.
//

import Cocoa
import CoreGraphics
import os

private let log = Logger(subsystem: "app.xdrgamma", category: "Gamma")

@MainActor
final class GammaController {

    // MARK: - Tuning

    /// Below this headroom we treat HDR as not yet engaged.
    private let hdrReadyThreshold: CGFloat = 1.05
    /// How long to wait for the panel to ramp up before calling it a failure.
    private let hdrEngageTimeout: TimeInterval = 25
    /// Pause after a run of failures so we stop hammering pointlessly.
    private let retryCooldown: TimeInterval = 30
    private let maxConsecutiveFailures = 3
    /// White point drift past which we reapply the table.
    private let gammaTolerance: CGGammaValue = 0.003
    private let defaultPollInterval: Duration = .milliseconds(500)
    private let fastPollInterval: Duration = .milliseconds(16)
    private let fastPollDuration: TimeInterval = 30
    private let integrityPollInterval: Duration = .seconds(2)

    // MARK: - State

    /// What the user wants. Survives relaunch.
    private(set) var isUserEnabled = false
    /// Whether the boost is running right now.
    private(set) var isActive = false
    /// Boost dropped because of heat; it will return by itself.
    private(set) var isThermallySuspended = false

    /// User intensity, 0...1.
    private(set) var userBrightness: Float = 1.0

    let thermal = ThermalMonitor()

    private var savedTables: [CGDirectDisplayID: GammaTable] = [:]
    private var triggers: [CGDirectDisplayID: EDRTriggerController] = [:]
    private var engageTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var fadeTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var readyDisplays: Set<CGDirectDisplayID> = []
    private var failureCounts: [CGDirectDisplayID: Int] = [:]
    private var cooldownUntil: [CGDirectDisplayID: Date] = [:]
    private var fastPollUntil: Date?
    private var integrityTask: Task<Void, Never>?

    /// Fired on any state change so the menu can redraw.
    var onStateChange: (() -> Void)?

    // MARK: - Lifecycle

    init() {
        userBrightness = Settings.shared.userBrightness
        isUserEnabled = Settings.shared.enabled

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        thermal.onChange = { [weak self] in
            guard let self else { return }
            log.info("Thermal state: \(self.thermal.localizedState)")
            self.reevaluate()
        }
    }

    /// Restores saved state. Called once after launch.
    func restoreSavedState() {
        guard isUserEnabled else { return }
        reevaluate()
    }

    var compatibleScreens: [NSScreen] {
        NSScreen.screens.filter { $0.supportsBrightnessBoost }
    }

    // MARK: - User intent

    func toggle() {
        setUserEnabled(!isUserEnabled)
    }

    func setUserEnabled(_ enabled: Bool) {
        isUserEnabled = enabled
        Settings.shared.enabled = enabled
        reevaluate()
    }

    func setUserBrightness(_ value: Float) {
        userBrightness = max(0, min(1, value))
        Settings.shared.userBrightness = userBrightness
        guard isActive else { return }
        for id in readyDisplays {
            applyFactor(displayId: id, animated: false)
        }
        onStateChange?()
    }

    /// The user flipped the thermal preference — recompute.
    func thermalPreferenceChanged() {
        reevaluate()
    }

    // MARK: - Reconciling intent with conditions

    private var thermalBlocks: Bool {
        Settings.shared.disableOnThermalPressure && thermal.isUnderPressure
    }

    private func reevaluate() {
        let blocked = thermalBlocks
        let shouldRun = isUserEnabled && !blocked

        let wasSuspended = isThermallySuspended
        isThermallySuspended = isUserEnabled && blocked

        if isThermallySuspended && !wasSuspended {
            log.info("Throttling (\(self.thermal.localizedState)) — dropping the boost")
        } else if !isThermallySuspended && wasSuspended {
            log.info("Temperature back to normal — restoring the boost")
        }

        if shouldRun {
            activate()
        } else {
            deactivate()
        }
        onStateChange?()
    }

    // MARK: - Actually running

    private func activate() {
        guard !isActive else { return }
        let screens = compatibleScreens
        guard !screens.isEmpty else {
            log.error("No compatible displays (potential EDR headroom <= 1.5)")
            return
        }
        isActive = true
        log.info("Activating on \(screens.count) display(s)")

        for screen in screens {
            startDisplay(screen)
        }
        startIntegrityPoll()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        log.info("Deactivating")

        integrityTask?.cancel()
        integrityTask = nil

        for (_, task) in engageTasks { task.cancel() }
        engageTasks.removeAll()
        for (_, task) in fadeTasks { task.cancel() }
        fadeTasks.removeAll()

        // Gamma first, windows second: the other order flashes the screen.
        for (id, table) in savedTables {
            table.apply(to: id, factor: 1.0)
        }
        savedTables.removeAll()

        for (_, trigger) in triggers { trigger.close() }
        triggers.removeAll()

        readyDisplays.removeAll()
    }

    /// Emergency reset — on quit and on signals.
    func restoreAndStop() {
        deactivate()
        GammaTable.restoreSystemColorState()
    }

    // MARK: - Per-display startup

    private func startDisplay(_ screen: NSScreen) {
        guard let id = screen.displayId else { return }
        guard savedTables[id] == nil else { return }

        guard let table = GammaTable.capture(displayId: id) else {
            log.error("Could not read the transfer table for display \(id)")
            return
        }
        savedTables[id] = table

        let trigger = EDRTriggerController(screen: screen)
        trigger.open()
        triggers[id] = trigger

        engageTasks[id]?.cancel()
        engageTasks[id] = Task { @MainActor in
            await self.engageHDR(displayId: id)
        }
    }

    private func stopDisplay(_ id: CGDirectDisplayID) {
        engageTasks[id]?.cancel()
        engageTasks.removeValue(forKey: id)
        fadeTasks[id]?.cancel()
        fadeTasks.removeValue(forKey: id)

        if let table = savedTables[id] {
            table.apply(to: id, factor: 1.0)
        }
        savedTables.removeValue(forKey: id)

        triggers[id]?.close()
        triggers.removeValue(forKey: id)

        readyDisplays.remove(id)
        failureCounts.removeValue(forKey: id)
        cooldownUntil.removeValue(forKey: id)
    }

    // MARK: - Waiting for HDR

    /// The panel does not reach full headroom instantly — it ramps over
    /// seconds. Touching gamma before that gains nothing and blows out the
    /// picture in the meantime.
    private func engageHDR(displayId: CGDirectDisplayID) async {
        while !Task.isCancelled && isActive {
            if let until = cooldownUntil[displayId], Date() < until {
                let remaining = until.timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(1, remaining)))
                continue
            }

            let deadline = Date().addingTimeInterval(hdrEngageTimeout)
            var engaged = false

            while !Task.isCancelled && isActive && Date() < deadline {
                guard let screen = screen(for: displayId) else { break }
                if screen.currentEDRHeadroom > hdrReadyThreshold {
                    engaged = true
                    break
                }
                try? await Task.sleep(for: currentPollInterval())
            }

            guard !Task.isCancelled && isActive else { return }

            if engaged {
                failureCounts[displayId] = 0
                cooldownUntil.removeValue(forKey: displayId)
                readyDisplays.insert(displayId)
                log.info("HDR engaged on display \(displayId), applying gamma")
                applyFactor(displayId: displayId, animated: true)
                onStateChange?()
                return
            }

            let failures = (failureCounts[displayId] ?? 0) + 1
            failureCounts[displayId] = failures
            log.error("HDR did not engage on display \(displayId) (attempt \(failures))")

            if failures >= maxConsecutiveFailures {
                cooldownUntil[displayId] = Date().addingTimeInterval(retryCooldown)
                failureCounts[displayId] = 0
            }
        }
    }

    private func currentPollInterval() -> Duration {
        if let until = fastPollUntil, Date() < until {
            return fastPollInterval
        }
        return defaultPollInterval
    }

    // MARK: - Computing and applying the multiplier

    /// The higher the headroom, the lower the system brightness slider sits,
    /// and the less boost is needed. At the top of the slider headroom equals
    /// referenceEdr and we hand over the whole bonusGamma.
    private func gammaFactor(for screen: NSScreen) -> Float {
        let (referenceEdr, bonusGamma) = screenReferenceGamma(screen)
        let maximumEdr: Float = 16.0
        guard maximumEdr > referenceEdr else { return 1 }

        let currentEdr = Float(screen.currentEDRHeadroom)
        let clamped = min(max(currentEdr, referenceEdr), maximumEdr)
        let full = 1 + bonusGamma * (1 - (clamped - referenceEdr) / (maximumEdr - referenceEdr))
        return 1 + (full - 1) * userBrightness
    }

    private func applyFactor(displayId: CGDirectDisplayID, animated: Bool) {
        guard let screen = screen(for: displayId),
              let table = savedTables[displayId]
        else { return }

        let target = gammaFactor(for: screen)
        let current = table.appliedFactor

        fadeTasks[displayId]?.cancel()

        guard animated, abs(target - current) > 0.005 else {
            table.apply(to: displayId, factor: target)
            return
        }

        fadeTasks[displayId] = Task { @MainActor in
            let steps = 15
            for step in 1...steps {
                if Task.isCancelled { return }
                let t = Float(step) / Float(steps)
                table.apply(to: displayId, factor: current + (target - current) * t)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: - Holding the table

    /// The system resets our table now and then: sleep, color profile changes,
    /// the ambient light sensor, GPU switching. Catch the drift and reapply.
    private func startIntegrityPoll() {
        integrityTask?.cancel()
        integrityTask = Task { @MainActor in
            while !Task.isCancelled && isActive {
                try? await Task.sleep(for: integrityPollInterval)
                guard !Task.isCancelled && isActive else { return }

                for id in readyDisplays {
                    guard let screen = screen(for: id),
                          let table = savedTables[id]
                    else { continue }

                    // HDR dropped out — pull the boost and wait for it again.
                    if screen.currentEDRHeadroom <= hdrReadyThreshold {
                        log.info("HDR lost on display \(id), rolling gamma back")
                        table.apply(to: id, factor: 1.0)
                        readyDisplays.remove(id)
                        engageTasks[id]?.cancel()
                        engageTasks[id] = Task { @MainActor in
                            await self.engageHDR(displayId: id)
                        }
                        onStateChange?()
                        continue
                    }

                    if table.hasDrifted(on: id, tolerance: gammaTolerance) {
                        log.info("Display \(id) table was reset by the system, reapplying")
                        table.apply(to: id, factor: table.appliedFactor)
                    } else {
                        // Headroom moves with the slider — recompute.
                        applyFactor(displayId: id, animated: false)
                    }
                }
            }
        }
    }

    // MARK: - Reacting to the system

    @objc private func screenParametersChanged() {
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
        guard isActive else { return }

        let screens = compatibleScreens
        let activeIds = Set(screens.compactMap { $0.displayId })

        for id in Set(savedTables.keys).subtracting(activeIds) {
            stopDisplay(id)
        }
        for screen in screens {
            guard let id = screen.displayId else { continue }
            if savedTables[id] == nil {
                startDisplay(screen)
            } else {
                triggers[id]?.update(screen: screen)
            }
        }
        onStateChange?()
    }

    @objc private func systemDidWake() {
        guard isActive else { return }
        fastPollUntil = Date().addingTimeInterval(fastPollDuration)
        // After sleep the panel almost always leaves HDR — restart the cycle.
        for id in Array(savedTables.keys) {
            readyDisplays.remove(id)
            savedTables[id]?.apply(to: id, factor: 1.0)
            engageTasks[id]?.cancel()
            engageTasks[id] = Task { @MainActor in
                await self.engageHDR(displayId: id)
            }
        }
    }

    private func screen(for displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayId == displayId }
    }

    // MARK: - Diagnostics for the menu

    func statusLine() -> String {
        if isThermallySuspended {
            return "Paused: \(thermal.localizedState)"
        }
        guard let screen = NSScreen.main else { return "No display found" }
        let current = String(format: "%.2f", screen.currentEDRHeadroom)
        let potential = String(format: "%.2f", screen.potentialEDRHeadroom)
        let factor = screen.displayId.flatMap { savedTables[$0]?.appliedFactor } ?? 1.0
        let factorStr = String(format: "%.2f", factor)
        return "Headroom \(current) / \(potential) · gamma ×\(factorStr)"
    }

    func thermalLine() -> String {
        "Temperature: \(thermal.localizedState)"
    }
}
