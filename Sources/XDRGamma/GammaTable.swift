//
//  GammaTable.swift
//  XDRGamma
//
//  A snapshot of the display's stock transfer table, plus scaling.
//  Values above 1.0 reach into the EDR headroom — that is what produces the
//  extra brightness, but only while the panel is held in HDR mode
//  (see EDRTrigger).
//

import Cocoa
import CoreGraphics

final class GammaTable {
    static let tableSize: UInt32 = 256

    private(set) var red: [CGGammaValue]
    private(set) var green: [CGGammaValue]
    private(set) var blue: [CGGammaValue]

    /// The most recently applied multiplier.
    private(set) var appliedFactor: Float = 1.0

    private init(red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Reads the display's current table. Call this BEFORE touching gamma.
    static func capture(displayId: CGDirectDisplayID) -> GammaTable? {
        let count = Int(tableSize)
        var red = [CGGammaValue](repeating: 0, count: count)
        var green = [CGGammaValue](repeating: 0, count: count)
        var blue = [CGGammaValue](repeating: 0, count: count)
        var sampleCount: UInt32 = 0

        let result = CGGetDisplayTransferByTable(
            displayId, tableSize, &red, &green, &blue, &sampleCount
        )
        guard result == .success, sampleCount > 0 else { return nil }
        return GammaTable(red: red, green: green, blue: blue)
    }

    /// Applies the captured table scaled by factor.
    /// A factor of 1.0 restores the display to its original state.
    @discardableResult
    func apply(to displayId: CGDirectDisplayID, factor: Float) -> CGError {
        var newRed = red
        var newGreen = green
        var newBlue = blue

        for i in 0..<newRed.count {
            newRed[i] *= factor
            newGreen[i] *= factor
            newBlue[i] *= factor
        }

        let result = CGSetDisplayTransferByTable(
            displayId, GammaTable.tableSize, &newRed, &newGreen, &newBlue
        )
        if result == .success {
            appliedFactor = factor
        }
        return result
    }

    /// The white point we expect to see for a given multiplier.
    func expectedWhitePoint(factor: Float) -> (Float, Float, Float)? {
        guard let r = red.last, let g = green.last, let b = blue.last else { return nil }
        return (r * factor, g * factor, b * factor)
    }

    /// Detects whether the system reset our table (sleep, profile switch,
    /// ambient light sensor). Returns true when the real white point has
    /// drifted away from the expected one.
    func hasDrifted(on displayId: CGDirectDisplayID, tolerance: CGGammaValue) -> Bool {
        guard let expected = expectedWhitePoint(factor: appliedFactor),
              let current = GammaTable.capture(displayId: displayId),
              let curR = current.red.last,
              let curG = current.green.last,
              let curB = current.blue.last
        else { return false }

        return abs(curR - expected.0) > tolerance
            || abs(curG - expected.1) > tolerance
            || abs(curB - expected.2) > tolerance
    }

    /// Emergency restore for every display. Safe to call from anywhere.
    nonisolated static func restoreSystemColorState() {
        CGDisplayRestoreColorSyncSettings()
    }
}
