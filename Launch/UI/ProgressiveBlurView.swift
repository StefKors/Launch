import AppKit
import SwiftUI

/// A blur whose radius changes from point to point: full strength in the
/// middle, thinning to none at the edges, so there is no seam where blurred
/// meets sharp. (Fading a uniform blur with a mask looks like frosted glass
/// dissolving; this looks like depth of field.) A dark tint, faded out the same
/// way, sits on top of it for legibility.
///
/// It is the blur of an `NSVisualEffectView` with its Gaussian filter swapped
/// for Core Animation's `variableBlur`, which reads its per-pixel radius from
/// a mask image. Both the filter and the layer it lives on are private, so
/// everything here is checked at runtime and `isSupported` says whether it
/// worked; callers fall back to a plain material when it is false.
///
/// The view is created once and never resized: the pool's height is part of
/// the mask, and `ProgressiveBlurView` eases it towards `Spec.height` itself,
/// so the list changing under it costs a small mask per frame, not a SwiftUI
/// layout pass and a new view.
struct ProgressiveBlur: NSViewRepresentable {
    struct Spec: Equatable {
        var radius: CGFloat
        var blur: BlurProfile
        var tint: BlurProfile
        var tintOpacity: CGFloat
        /// The height of the pool when the panel opens, and what it returns to
        /// whenever the panel is hidden.
        var restingHeight: CGFloat
        /// The height it eases towards.
        var height: CGFloat
        /// 1 for the full blur and tint, 0 for none; it eases towards this. Set
        /// to 0 and back to 1 to blur out and in.
        var presence: CGFloat
    }

    let spec: Spec

    static var isSupported: Bool { ProgressiveBlurView.isSupported }

    func makeNSView(context: Context) -> ProgressiveBlurView {
        let view = ProgressiveBlurView()
        // Before it is in a window, so its first frame is already the right shape.
        view.update(spec)
        return view
    }

    func updateNSView(_ view: ProgressiveBlurView, context: Context) {
        view.update(spec)
    }
}

/// How strength falls off from a full core to nothing, per side (a side can
/// fade over a different distance, because the window's margin above the
/// content is not the one below it). All in points.
struct BlurProfile: Equatable {
    /// Distance from each edge of the view to the full-strength core.
    var inset: EdgeInsets
    /// Distance, past the core, over which it fades to nothing.
    var falloff: EdgeInsets
    /// The pool is this tall, counted from the top, and the rest of the view is
    /// left alone. Nil means all of it.
    var height: CGFloat?

    private func fade(_ outside: CGFloat, over distance: CGFloat) -> CGFloat {
        distance > 0 ? max(0, outside) / distance : 0
    }

    /// How far outside the core a column is, as a fraction of the fade.
    func horizontalFade(at x: CGFloat, width: CGFloat) -> CGFloat {
        // Both sides are looked at, because a pool can be small enough that the
        // fades from either side overlap and it never reaches full strength.
        max(
            fade(inset.leading - x, over: falloff.leading),
            fade(x - (width - inset.trailing), over: falloff.trailing)
        )
    }

    /// The same for a row, `y` counted down from the top.
    func verticalFade(at y: CGFloat, height viewHeight: CGFloat) -> CGFloat {
        max(
            fade(inset.top - y, over: falloff.top),
            fade(y - ((height ?? viewHeight) - inset.bottom), over: falloff.bottom)
        )
    }

    /// Strength from 0 to 1 once both fades are known.
    static func strength(dx: CGFloat, dy: CGFloat) -> CGFloat {
        // Corners fade along the diagonal, so the pool is rounded.
        let t = min(1, (dx * dx + dy * dy).squareRoot())
        // Smootherstep: no visible start or end to the fade.
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        return 1 - eased
    }

    /// Strength at a point, `y` counted down from the top.
    func strength(x: CGFloat, y: CGFloat, in size: CGSize) -> CGFloat {
        Self.strength(dx: horizontalFade(at: x, width: size.width), dy: verticalFade(at: y, height: size.height))
    }

    /// Strength as the alpha of a small image, to be stretched over the whole
    /// view. It changes smoothly, so a fraction of the resolution is not
    /// visible. The fades are worked out once per column and per row, not per
    /// pixel: this runs every frame while the pool changes height.
    func maskImage(size: CGSize, scale: CGFloat = 0.25) -> CGImage? {
        let width = max(2, Int((size.width * scale).rounded()))
        let height = max(2, Int((size.height * scale).rounded()))
        let dx = (0..<width).map { horizontalFade(at: (CGFloat($0) + 0.5) / CGFloat(width) * size.width, width: size.width) }
        let dy = (0..<height).map { verticalFade(at: (CGFloat($0) + 0.5) / CGFloat(height) * size.height, height: size.height) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for row in 0..<height {
                for column in 0..<width {
                    let alpha = UInt8((Self.strength(dx: dx[column], dy: dy[row]) * 255).rounded())
                    // Premultiplied white.
                    let offset = (row * width + column) * 4
                    buffer[offset] = alpha
                    buffer[offset + 1] = alpha
                    buffer[offset + 2] = alpha
                    buffer[offset + 3] = alpha
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

final class ProgressiveBlurView: NSVisualEffectView {
    private var spec: ProgressiveBlur.Spec?
    /// The pool's height as drawn right now; it eases towards `spec.height`.
    private var displayedHeight: CGFloat?
    /// The same for `spec.presence`. It starts at nothing, so the first frame
    /// has no blur and it grows in.
    private var displayedPresence: CGFloat = 0
    private var maskCache: (key: MaskKey, blur: CGImage, tint: CGImage)?
    private var appliedKey: AppliedKey?
    private var observer: CFRunLoopObserver?
    private var displayLink: CADisplayLink?
    private let tintLayer = CALayer()
    private let tintMask = CALayer()

    private struct AppliedKey: Equatable {
        var size: CGSize
        var spec: ProgressiveBlur.Spec
        var height: CGFloat
        var presence: CGFloat
        var isMoving: Bool
    }

    /// What the masks depend on; presence only scales the radius and the tint,
    /// so fading in and out reuses them.
    private struct MaskKey: Equatable {
        var size: CGSize
        var blur: BlurProfile
        var tint: BlurProfile
        var scale: CGFloat
    }

    /// Seconds for the pool to cover most of the way to a new height.
    private static let easing: CGFloat = 0.06
    /// The same for the blur fading in and out. It is nearly there after three
    /// of these, which is the length of the launcher's own transition.
    private static let presenceEasing = CGFloat(LauncherMetrics.transitionDuration) / 3

    static let isSupported: Bool = {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              filterClass.responds(to: NSSelectorFromString("filterWithType:")),
              NSClassFromString("CABackdropLayer") != nil
        else { return false }
        let types = filterClass.perform(NSSelectorFromString("filterTypes"))?.takeUnretainedValue() as? [String]
        return types?.contains("variableBlur") == true
    }()

    init() {
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        // Until the variable blur is in place, what would show is the plain
        // material: a hard-edged rectangle. Show nothing instead.
        alphaValue = 0
        tintLayer.mask = tintMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit { stopWatching() }

    func update(_ spec: ProgressiveBlur.Spec) {
        let previous = self.spec
        self.spec = spec
        if displayedHeight == nil { displayedHeight = spec.restingHeight }
        if previous?.height != spec.height || previous?.presence != spec.presence, window?.isVisible == true {
            displayLink?.isPaused = false
        }
        applyIfNeeded()
    }

    override func layout() {
        super.layout()
        applyIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        appliedKey = nil
        if window == nil { stopWatching() } else { startWatching() }
        applyIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The view rebuilds its layers when the appearance changes.
        appliedKey = nil
        applyIfNeeded()
    }

    // MARK: Staying in place

    /// The view builds its backdrop layer a moment after it joins a window and
    /// rebuilds it when it likes (the panel being shown again, the appearance,
    /// the key window changing), always with the plain material. Nothing says
    /// when, so this also runs on every turn of the run loop, before the
    /// screen is updated: the plain material is put right back to the variable
    /// blur before it is ever drawn. It costs a look at one layer's filters.
    private func startWatching() {
        guard observer == nil else { return }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
            nonisolated(unsafe) let view = self
            MainActor.assumeIsolated { view?.runLoopTurn() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer

        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopWatching() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    private func runLoopTurn() {
        // A panel that is hidden starts its next showing from the small pool
        // and no blur, so it never opens big and shrinks, and it blurs in.
        if window?.isVisible != true, let spec {
            displayedHeight = spec.restingHeight
            displayedPresence = 0
            displayLink?.isPaused = true
        }
        applyIfNeeded()
    }

    // MARK: Height

    @objc private func step(_ link: CADisplayLink) {
        guard let spec, let current = displayedHeight, window?.isVisible == true else {
            link.isPaused = true
            return
        }
        let target = min(spec.height, bounds.height)
        let seconds = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        let amount = 1 - exp(-CGFloat(seconds) / Self.easing)
        let presenceAmount = 1 - exp(-CGFloat(seconds) / Self.presenceEasing)
        var height = current + (target - current) * amount
        var presence = displayedPresence + (spec.presence - displayedPresence) * presenceAmount
        if abs(target - height) < 0.5 { height = target }
        if abs(spec.presence - presence) < 0.01 { presence = spec.presence }
        if height == target, presence == spec.presence { link.isPaused = true }
        displayedHeight = height
        displayedPresence = presence
        applyIfNeeded()
    }

    private var isMoving: Bool { displayLink?.isPaused == false }

    // MARK: Layers

    private func applyIfNeeded() {
        guard Self.isSupported, window != nil, bounds.width > 1, bounds.height > 1,
              let spec, let displayedHeight,
              let root = layer, let backdrop = Self.backdropLayer(in: root)
        else { return }

        let height = min(displayedHeight, bounds.height)
        let presence = displayedPresence
        let key = AppliedKey(size: bounds.size, spec: spec, height: (height * 2).rounded() / 2, presence: (presence * 100).rounded() / 100, isMoving: isMoving)
        if key == appliedKey, Self.hasVariableBlur(backdrop), tintLayer.superlayer === root { return }

        // A low-resolution mask while the pool moves; it is not on screen long
        // enough to see, and it has to be redrawn every frame. The still pool
        // gets a better one.
        let scale: CGFloat = key.isMoving ? 0.15 : 0.3
        var blur = spec.blur
        blur.height = height
        var tint = spec.tint
        tint.height = height
        let maskKey = MaskKey(size: bounds.size, blur: blur, tint: tint, scale: scale)
        if maskCache?.key != maskKey {
            guard let blurImage = blur.maskImage(size: bounds.size, scale: scale),
                  let tintImage = tint.maskImage(size: bounds.size, scale: scale)
            else { return }
            maskCache = (maskKey, blurImage, tintImage)
        }
        guard let masks = maskCache,
              // A radius of exactly nothing is not a valid blur; barely any is.
              let filter = makeFilter(radius: max(0.01, spec.radius * presence), mask: masks.blur)
        else { return }
        appliedKey = key

        // The backdrop is captured at an eighth of the resolution, which is
        // fine for a uniform blur but smears everything, even where the radius
        // is zero, and ends in a visible seam at the edge. Take it at full size.
        backdrop.setValue(1.0, forKey: "scale")
        // Only the variable blur. The layer's other filters (it saturates and
        // normalises HDR) are for a material, and they change the colour of
        // everything inside the view, even where the radius is zero, which
        // draws the view's rectangle onto the screen.
        backdrop.filters = [filter]
        // The material's own tint and highlight layers would put a flat
        // rectangle back.
        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop {
            sibling.isHidden = true
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if tintLayer.superlayer !== root { root.addSublayer(tintLayer) }
        tintLayer.zPosition = 1
        tintLayer.frame = root.bounds
        tintLayer.backgroundColor = NSColor.black.withAlphaComponent(spec.tintOpacity * presence).cgColor
        tintMask.frame = tintLayer.bounds
        tintMask.contents = masks.tint
        CATransaction.commit()

        alphaValue = 1
    }

    private func makeFilter(radius: CGFloat, mask: CGImage?) -> NSObject? {
        guard let mask,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue("variableBlur", forKey: "name")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    private static func hasVariableBlur(_ backdrop: CALayer) -> Bool {
        guard let filters = backdrop.filters, filters.count == 1 else { return false }
        return (filters[0] as AnyObject).value(forKey: "name") as? String == "variableBlur"
    }

    private static func backdropLayer(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)) == "CABackdropLayer" { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = backdropLayer(in: sublayer) { return found }
        }
        return nil
    }
}
