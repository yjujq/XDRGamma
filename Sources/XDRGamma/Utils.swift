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

/// Peak luminance of an XDR panel: small areas, short bursts.
private let peakNits: Float = 1600

/// What the panel can hold indefinitely across the whole screen — Apple's
/// sustained XDR rating, and the ceiling this app aims for. Going past it would
/// only be honoured in bursts, and would heat the panel for nothing.
private let sustainedNits: Float = 1000

/// Returns (referenceEdr, bonusGamma) for a display.
///
/// Both are derived from two facts about the panel rather than hand-tuned.
///
/// referenceEdr is the headroom the system reports at the top of the brightness
/// slider, which is exactly peak ÷ SDR white. Confirmed by measurement on
/// Mac15,7: at 100% the slider reports 2.667, and 1600 ÷ 600 = 2.667.
///
/// bonusGamma is how far past SDR white the table may be scaled, so the ceiling
/// is (1 + bonusGamma) × SDR white. Aiming at the sustained rating lands every
/// panel on the same 1000 nits: ×1.67 up from 600, ×2.0 up from 500. Both stay
/// inside the headroom actually granted at full brightness (2.67 and 3.2), so
/// the boost never asks for more than the display is offering.
func screenReferenceGamma(_ screen: NSScreen) -> (referenceEdr: Float, bonusGamma: Float) {
    // Whether this panel's SDR white sits at 600 nits or 500. External XDR
    // displays are treated as 600, which is what the previous hand-tuned
    // reference headroom of 2.66 implied for them.
    let sdrWhiteNits: Float
    if screen.isBuiltin, let model = modelIdentifier(), !sdr600NitsDevices.contains(model) {
        sdrWhiteNits = 500
    } else {
        sdrWhiteNits = 600
    }

    return (peakNits / sdrWhiteNits, sustainedNits / sdrWhiteNits - 1)
}
