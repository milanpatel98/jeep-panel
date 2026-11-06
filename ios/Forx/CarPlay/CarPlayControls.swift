import CarPlay
import CoreGraphics
import Foundation
import Observation
import UIKit

// MARK: - Pan (pure, tested)

/// One finger drag on the CarPlay screen, from CarPlay's pan callbacks (cumulative translation).
/// The first 10 pt decide the axis and lock it for the whole drag. Sideways turns the Jeep 1:1
/// from where it locked (or, with the map open, slides the divider); up and down works the roof
/// strip: the thumb follows the finger and every 44 pt crossed is one roof step.
nonisolated struct CarPlayPan: Sendable, Equatable {
    enum Axis: Sendable, Equatable { case horizontal, vertical }

    enum Action: Sendable, Equatable {
        /// Turn the Jeep by this many degrees (drag right: positive).
        case spin(Double)
        /// The sideways drag ended (home): the Jeep may glide back.
        case release
        /// The map's divider follows the finger: this far right of where it was.
        case divider(Double)
        /// The divider drag ended at this offset, with this sideways velocity (pt/s).
        case dividerRelease(Double, Double)
        /// The strip's thumb is pulled this far (down positive) from the step it's on.
        case strip(Double)
        /// Take parts off (+1, drag up) or put them back (−1, drag down), one step.
        case roofStep(Int)
        /// The vertical drag ended: the thumb snaps to its step.
        case stripRelease
    }

    static let lockDistance: Double = 10
    static let degreesPerPoint: Double = 0.4
    /// One roof step per this many points up or down.
    static let stepPoints: Double = 44

    /// With the map open a sideways drag moves the divider instead of turning the Jeep.
    let mapOpen: Bool
    private(set) var axis: Axis? = nil
    private var lastX: Double = 0
    private var lastDx: Double = 0
    private var startY: Double = 0
    /// Steps already taken this drag (up positive).
    private var steps = 0

    init(mapOpen: Bool = false) {
        self.mapOpen = mapOpen
    }

    mutating func update(_ t: CGPoint) -> [Action] {
        guard t.x.isFinite, t.y.isFinite else { return [] }
        guard let axis else {
            guard Double(hypot(t.x, t.y)) >= Self.lockDistance else { return [] }
            self.axis = abs(t.x) >= abs(t.y) ? .horizontal : .vertical
            lastX = Double(t.x)
            startY = Double(t.y)
            return []
        }
        switch axis {
        case .horizontal:
            if mapOpen {
                lastDx = Double(t.x) - lastX
                return [.divider(lastDx)]
            }
            let dx = Double(t.x) - lastX
            lastX = Double(t.x)
            return dx == 0 ? [] : [.spin(dx * Self.degreesPerPoint)]
        case .vertical:
            let dy = Double(t.y) - startY
            let wanted = Int((-dy / Self.stepPoints).rounded(.towardZero))
            var out: [Action] = []
            while wanted != steps {   // a fast move can cross more than one step
                let sign = wanted > steps ? 1 : -1
                out.append(.roofStep(sign))
                steps += sign
            }
            out.append(.strip(dy + Double(steps) * Self.stepPoints))
            return out
        }
    }

    mutating func end(velocity: CGPoint) -> [Action] {
        switch axis {
        case .horizontal: return mapOpen ? [.dividerRelease(lastDx, Double(velocity.x))] : [.release]
        case .vertical: return [.stripRelease]
        case nil: return []
        }
    }
}

// MARK: - What the screen is doing (observable)

/// The dashboard's own state, beside the store's: the map open or not, the Jeep's view, the
/// divider while a finger drags it, and whether the 3D page is up. Observed by the scene.
@Observable
final class DashboardMotion {
    var mapOpen = false
    var mode: JeepMode = .hero
    /// The divider's live offset to the right while a finger drags it; 0 otherwise.
    var dividerDx: CGFloat = 0
    /// The 3D page: `blank` until it has painted its loading screen, `loading` with the model's
    /// progress, `ready` once the Jeep is on screen.
    enum Page: Equatable { case blank, loading(Double), ready }
    var page: Page = .blank

    init() {}
}

// MARK: - Fingers → 3D Jeep

/// Carries CarPlay's gestures (from `CarPlayTemplates`) to the 3D page (`JeepEmbedView` sets `send`)
/// and the dashboard (`motion`): a sideways drag turns the Jeep or slides the map's divider, an
/// up-and-down drag works the roof strip, two fingers zoom (iOS 26 cars) or turn it.
final class JeepGestures {
    /// Runs `window.jeepEmbed.<call>` on the page; nil until the page's view is up.
    var send: ((String) -> Void)?
    /// Sets the roof (the strip's steps); `AppModel.roof` in the app, recorded in tests.
    var setRoof: (String) -> Void
    /// The roof the Jeep shows now (its strip step); the templates keep it current.
    var roof = "on"
    /// Closes the map when a divider drag lets go far enough; set by the templates.
    var closeMap: (() -> Void)?
    let motion: DashboardMotion
    /// The divider's travel to the right edge, in points; the dashboard layout sets it.
    var dividerTravel: CGFloat = 400
    /// Past this share of the travel (or flicked faster than `closeVelocity`) the map closes.
    static let closeShare: CGFloat = 0.25
    static let closeVelocity: Double = 500

    private var pan: CarPlayPan?
    private var zoomBase: Double = 1
    private var zoomNow: Double = 1

    init(motion: DashboardMotion = DashboardMotion(), setRoof: @escaping (String) -> Void = { AppModel.roof = $0 }) {
        self.motion = motion
        self.setRoof = setRoof
    }

    // MARK: One finger

    func began() {
        pan = CarPlayPan(mapOpen: motion.mapOpen)
    }

    func changed(_ translation: CGPoint) {
        if pan == nil { began() }
        guard var p = pan else { return }
        let actions = p.update(translation)
        pan = p
        for action in actions { perform(action) }
    }

    func ended(_ velocity: CGPoint) {
        guard var p = pan else { return }
        pan = nil
        for action in p.end(velocity: velocity) { perform(action) }
    }

    /// Whatever is going on stops; the Jeep settles.
    func settle() {
        pan = nil
        perform(.release)
        perform(.stripRelease)
    }

    // MARK: Two fingers (iOS 26 cars)

    func zoomBegan() {
        zoomBase = zoomNow
    }

    func zoom(scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        zoomNow = min(1.8, max(1, zoomBase * Double(scale)))
        send?("zoom(\(zoomNow))")
    }

    func zoomEnded() {
        zoomBase = zoomNow
        zoomNow = 1  // it glides back to 1 after a moment
        send?("zoomEnd()")
    }

    /// A twist: turn the Jeep with it (radians, cumulative).
    private var rotationLast: Double = 0

    func rotationBegan() {
        rotationLast = 0
    }

    func rotate(_ radians: CGFloat) {
        guard radians.isFinite else { return }
        let delta = Double(radians) - rotationLast
        rotationLast = Double(radians)
        if delta != 0 { send?("spin(\(delta * 180 / .pi))") }
    }

    func rotationEnded() {
        send?("release()")
    }

    // MARK: Actions → the page and the dashboard

    /// Where the thumb sits for the roof `roof`: step 0 (Top on) … 3 (Doors off).
    var roofIndex: Int { CarPlayModel.roofIndex(roof) }

    private func perform(_ action: CarPlayPan.Action) {
        switch action {
        case .spin(let deg):
            send?("spin(\(deg))")
        case .release:
            send?("release()")
        case .divider(let dx):
            let clamped = min(max(0, dx), Double(dividerTravel))
            motion.dividerDx = CGFloat(clamped)
            if let json = regionJSON?(CGFloat(clamped)) { send?("layout(\(json))") }
        case .dividerRelease(let dx, let velocity):
            let far = dx > Double(dividerTravel) * Double(Self.closeShare) || velocity > Self.closeVelocity
            motion.dividerDx = 0
            if far { closeMap?() } else { send?("layoutRelease()") }
        case .strip(let dy):
            send?("strip(\(dy), \(roofIndex))")
        case .roofStep(let delta):
            let i = min(CarPlayModel.roofSteps.count - 1, max(0, roofIndex + delta))
            let next = CarPlayModel.roofSteps[i]
            if next != roof {
                roof = next
                setRoof(next)
            }
        case .stripRelease:
            send?("stripRelease()")
        }
    }

    /// The car's region JSON for a divider offset (the dashboard layout fills this in).
    var regionJSON: ((CGFloat) -> String)?
}

// MARK: - Apps tray

/// The Apps tray in the bottom-right corner. Open: the map buttons become the four favourite
/// apps and a panel with their names rises behind them. Closes after 8 s without use, on any
/// command, or when an app opens.
@Observable
final class AppTray {
    static let idleTimeout: Duration = .seconds(8)

    private(set) var isOpen = false
    @ObservationIgnored private var closer: Task<Void, Never>? = nil

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        if !isOpen { isOpen = true }
        armTimer()
    }

    func close() {
        closer?.cancel()
        closer = nil
        if isOpen { isOpen = false }
    }

    private func armTimer() {
        closer?.cancel()
        closer = Task { [weak self] in
            try? await Task.sleep(for: AppTray.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}

// MARK: - App icons

/// The apps' real icons (bundled as `appicon-<id>`, see ios/README.md), drawn into the iOS icon
/// shape or a circle at 3x. An icon that isn't bundled falls back to its SF Symbol on a plain tile.
enum AppIconArt {
    /// The iOS icon mask's corner, as a share of the side.
    static let corner: CGFloat = 0.2237

    static func bundled(_ app: CarPlayApp) -> UIImage? {
        UIImage(named: app.icon)
    }

    static func image(_ app: CarPlayApp, side: CGFloat, circle: Bool, dark: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let shape = circle
            ? UIBezierPath(ovalIn: rect)
            : UIBezierPath(roundedRect: rect, cornerRadius: side * corner)
        let icon = bundled(app)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            shape.addClip()
            if let icon {
                icon.draw(in: rect)
            } else {
                let tile = dark
                    ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
                    : UIColor.white
                tile.setFill()
                shape.fill()
                let config = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
                let tint: UIColor = dark ? .white : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
                if let glyph = UIImage(systemName: app.symbol, withConfiguration: config)?
                    .withTintColor(tint, renderingMode: .alwaysOriginal) {
                    let s = glyph.size
                    glyph.draw(in: CGRect(x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height))
                }
            }
            // a hairline edge, as the Home Screen draws on light icons
            UIColor.black.withAlphaComponent(0.08).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
