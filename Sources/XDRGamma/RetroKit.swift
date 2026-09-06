//
//  RetroKit.swift
//  XDRGamma
//
//  The look: a terminal panel drawn by hand — teal ground, a thin rule with the
//  title cut into its top edge, monospace throughout, and controls that are
//  typography rather than widgets. Checkboxes are [x], the slider is a run of
//  cells, buttons carry a hard offset shadow instead of a gradient.
//
//  Nothing here uses a system control, because a stock NSButton or NSSlider
//  would drag its own material and corner radius into the picture and break the
//  illusion immediately.
//

import Cocoa

enum Retro {

    // MARK: - Palette

    static let ground     = NSColor(srgbRed: 0.310, green: 0.624, blue: 0.635, alpha: 1) // teal
    static let ink        = NSColor.black
    static let chipInk    = NSColor.white
    static let paper      = NSColor.white
    static let highlight  = NSColor(srgbRed: 0.949, green: 0.949, blue: 0.376, alpha: 1) // marker yellow
    static let dim        = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.55)

    // MARK: - Type

    /// Menlo is the closest thing installed to the wide, squarish grid the look
    /// wants; the system monospace is the fallback if it ever goes missing.
    static func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        if let menlo = NSFont(name: bold ? "Menlo-Bold" : "Menlo", size: size) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func label(_ text: String, size: CGFloat = 13, bold: Bool = false,
                      color: NSColor = Retro.ink, align: NSTextAlignment = .left) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = mono(size, bold: bold)
        f.textColor = color
        f.alignment = align
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.cell?.wraps = true
        return f
    }
}

// MARK: - The panel

/// Teal ground, a thin rule inset from the edge, and the title sitting in a
/// black chip cut into the top of that rule.
final class RetroPanelView: NSView {

    var title: String = "" { didSet { needsDisplay = true } }

    /// Deep enough to leave the title chip room above the rule it straddles.
    private let innerInset: CGFloat = 19

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds

        Retro.ground.setFill()
        b.fill()

        Retro.ink.setStroke()
        let inner = NSBezierPath(rect: b.insetBy(dx: innerInset, dy: innerInset))
        inner.lineWidth = 1.5
        inner.stroke()

        guard !title.isEmpty else { return }

        // The chip straddles the inner rule, so the rule appears to pass behind it.
        let font = Retro.mono(15, bold: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Retro.chipInk]
        let size = (title as NSString).size(withAttributes: attrs)
        let chip = NSRect(x: (b.width - size.width - 28) / 2,
                          y: innerInset - size.height / 2 - 4,
                          width: size.width + 28,
                          height: size.height + 8)
        Retro.ink.setFill()
        chip.fill()
        (title as NSString).draw(at: NSPoint(x: chip.midX - size.width / 2,
                                             y: chip.midY - size.height / 2), withAttributes: attrs)
    }
}

// MARK: - Button

/// Black rule, flat fill, and a hard shadow offset down and right — no blur, no
/// gradient. Pressing moves the face onto the shadow, which is the whole
/// animation.
final class RetroButton: NSView {

    enum Kind { case primary, plain }

    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var kind: Kind { didSet { needsDisplay = true } }
    var onClick: () -> Void = {}

    private var pressed = false
    private var hovering = false
    private let offset: CGFloat = 6
    private let padding = NSSize(width: 22, height: 9)

    override var isFlipped: Bool { true }

    init(title: String, kind: Kind = .plain, action: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        super.init(frame: .zero)
        self.onClick = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var font: NSFont { Retro.mono(14, bold: true) }

    override var intrinsicContentSize: NSSize {
        let s = (title as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(s.width) + padding.width * 2 + offset,
                      height: ceil(s.height) + padding.height * 2 + offset)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if inside { onClick() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let face = NSRect(x: pressed ? offset : 0,
                          y: pressed ? offset : 0,
                          width: bounds.width - offset,
                          height: bounds.height - offset)

        if !pressed {
            Retro.ink.setFill()
            face.offsetBy(dx: offset, dy: offset).fill()
        }

        let fill: NSColor
        switch kind {
        case .primary: fill = Retro.highlight
        case .plain:   fill = Retro.paper
        }
        (hovering ? fill.blended(withFraction: 0.12, of: Retro.ground) ?? fill : fill).setFill()
        face.fill()

        Retro.ink.setStroke()
        let rule = NSBezierPath(rect: face.insetBy(dx: 1, dy: 1))
        rule.lineWidth = 2
        rule.stroke()

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Retro.ink]
        let s = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: face.midX - s.width / 2,
                                             y: face.midY - s.height / 2), withAttributes: attrs)
    }
}

// MARK: - Checkbox

/// `[x] Label` — the checkbox is the two brackets, so it lines up on the same
/// character grid as everything else.
final class RetroCheck: NSView {

    var title: String { didSet { needsDisplay = true } }
    var detail: String { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onToggle: () -> Void = {}

    private var hovering = false

    override var isFlipped: Bool { true }

    init(title: String, detail: String = "", action: @escaping () -> Void = {}) {
        self.title = title
        self.detail = detail
        super.init(frame: .zero)
        self.onToggle = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: detail.isEmpty ? 22 : 38)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    /// Claim the click: a view that ignores mouseDown never sees the mouseUp.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if isEnabled { onToggle() } }
    /// The panel floats and is often not the active window; without this the
    /// first click on it would only be an activating click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? Retro.ink : Retro.dim
        let font = Retro.mono(14)
        let box = "[\(isOn ? "x" : " ")]"

        if hovering && isEnabled {
            NSColor.black.withAlphaComponent(0.07).setFill()
            bounds.fill()
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (box as NSString).draw(at: NSPoint(x: 2, y: 1), withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 2 + 4 * font.maximumAdvancement.width, y: 1),
                                 withAttributes: attrs)

        guard !detail.isEmpty else { return }
        let sub: [NSAttributedString.Key: Any] = [.font: Retro.mono(11.5),
                                                  .foregroundColor: Retro.dim]
        (detail as NSString).draw(at: NSPoint(x: 2 + 4 * font.maximumAdvancement.width, y: 21),
                                  withAttributes: sub)
    }
}

// MARK: - Bar

/// The slider, drawn as a run of blocks between brackets. Click or drag
/// anywhere along it to set the value.
final class RetroBar: NSView {

    var value: Float = 1 { didSet { needsDisplay = true } }
    var onChange: (Float) -> Void = { _ in }

    private let cells = 24

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 24) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { set(from: event) }
    override func mouseDragged(with event: NSEvent) { set(from: event) }

    private var font: NSFont { Retro.mono(15) }
    private var unit: CGFloat { font.maximumAdvancement.width }
    private var trackStart: CGFloat { unit }              // just past the opening bracket

    private func set(from event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let raw = (x - trackStart) / (CGFloat(cells) * unit)
        value = Float(min(1, max(0, raw)))
        onChange(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Retro.ink]

        // Cells are drawn rather than typed: a run of block glyphs fuses into
        // one slab at full value, and the gaps are the whole point of a bar.
        let filled = Int((value * Float(cells)).rounded())
        let gap: CGFloat = 2
        let cellW = unit - gap
        let top: CGFloat = 5
        let cellH: CGFloat = 13

        for i in 0..<cells {
            let r = NSRect(x: trackStart + CGFloat(i) * unit, y: top, width: cellW, height: cellH)
            if i < filled {
                Retro.ink.setFill()
                r.fill()
            } else {
                Retro.ink.withAlphaComponent(0.28).setFill()
                NSRect(x: r.minX, y: r.midY - 1, width: r.width, height: 2).fill()
            }
        }

        ("[" as NSString).draw(at: NSPoint(x: 0, y: 2), withAttributes: attrs)
        ("]" as NSString).draw(at: NSPoint(x: trackStart + CGFloat(cells) * unit, y: 2),
                               withAttributes: attrs)

        let pct = String(format: "%3.0f%%", value * 100)
        (pct as NSString).draw(at: NSPoint(x: CGFloat(cells + 3) * unit, y: 2), withAttributes: attrs)
    }
}
