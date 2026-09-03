//
//  EDRTrigger.swift
//  XDRGamma
//
//  A 1x1 pixel window that keeps the panel in HDR mode.
//  It brightens nothing by itself — it only makes macOS grant EDR headroom,
//  which the gamma table then claims.
//
//  Everything here is public API.
//

import Cocoa
import MetalKit

final class EDRTriggerView: MTKView, MTKViewDelegate {

    private var commandQueue: MTLCommandQueue?
    private var didRenderFirstFrame = false
    var onFirstFrameRendered: (() -> Void)?

    init(clearValue: Double) {
        super.init(
            frame: NSRect(x: 0, y: 0, width: 1, height: 1),
            device: MTLCreateSystemDefaultDevice()
        )
        guard let device, let queue = device.makeCommandQueue() else {
            fatalError("No Metal device available")
        }
        commandQueue = queue
        delegate = self

        // Render exactly one pixel — there is no reason to allocate a
        // full-screen drawable.
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)

        // A float format plus an extended-linear color space is the only way
        // values above 1.0 survive unclipped and read as EDR content.
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        clearColor = MTLClearColorMake(clearValue, clearValue, clearValue, 1.0)

        // Headroom is revoked when the layer goes idle, so keep redrawing —
        // just cheaply.
        preferredFramesPerSecond = 5
        isPaused = false
        enableSetNeedsDisplay = false

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.isOpaque = false
            metalLayer.pixelFormat = .rgba16Float
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setClearValue(_ value: Double) {
        clearColor = MTLClearColorMake(value, value, value, 1.0)
    }

    func draw(in view: MTKView) {
        guard let commandQueue,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor),
              let drawable = view.currentDrawable
        else { return }

        // Empty pass: all we need is the clear color and a present.
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.didRenderFirstFrame else { return }
                self.didRenderFirstFrame = true
                self.onFirstFrameRendered?()
                self.onFirstFrameRendered = nil
            }
        }
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

final class EDRTriggerWindow: NSWindow {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        animationBehavior = .none
        alphaValue = 1
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EDRTriggerController {

    private let window: EDRTriggerWindow
    private let view: EDRTriggerView
    private(set) var screen: NSScreen

    init(screen: NSScreen, clearValue: Double = 1.6) {
        self.screen = screen
        self.window = EDRTriggerWindow()
        self.view = EDRTriggerView(clearValue: clearValue)
        window.contentView = view
    }

    func open() {
        reposition(screen: screen)
        window.orderFrontRegardless()
    }

    func update(screen: NSScreen) {
        self.screen = screen
        reposition(screen: screen)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    /// Tuck the pixel into the very top edge of the screen, behind the menu bar.
    private func reposition(screen: NSScreen) {
        var origin = screen.frame.origin
        origin.y += screen.frame.height - 1
        window.setFrameOrigin(origin)
    }
}
