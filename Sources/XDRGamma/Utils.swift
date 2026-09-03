//
//  Utils.swift
//  XDRGamma
//

import Cocoa

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltin: Bool {
        guard let id = displayId else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// Current EDR headroom: how many times the panel's peak exceeds SDR white.
    var currentEDRHeadroom: CGFloat {
        maximumExtendedDynamicRangeColorComponentValue
    }

    var potentialEDRHeadroom: CGFloat {
        maximumPotentialExtendedDynamicRangeColorComponentValue
    }

    /// A panel counts as boostable when its potential headroom is well above 1.
    var supportsBrightnessBoost: Bool {
        potentialEDRHeadroom > 1.5
    }
}

func modelIdentifier() -> String? {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return String(cString: buffer)
}

/// Panels whose SDR white is ~600 nits rather than ~500 (list from BrightIntosh).
/// They need a different reference headroom and boost ceiling.
let sdr600NitsDevices: Set<String> = [
    "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
    "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",
    "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9"
]

/// Returns (referenceEdr, bonusGamma) for a display.
///
/// referenceEdr is the headroom at the top of the system brightness slider
/// (1600 nits peak / 500 nits SDR white = 3.2 for the built-in XDR panel).
/// bonusGamma is the maximum gamma gain, so the boost ceiling is 1 + bonusGamma.
func screenReferenceGamma(_ screen: NSScreen) -> (referenceEdr: Float, bonusGamma: Float) {
    if screen.isBuiltin {
        if let model = modelIdentifier(), sdr600NitsDevices.contains(model) {
            return (2.66, 0.50)
        }
        return (3.2, 0.59)
    }
    // Pro Display XDR / Studio Display
    return (2.66, 0.6)
}
