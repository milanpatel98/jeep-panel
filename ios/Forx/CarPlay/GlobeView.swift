import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Fit (pure, tested)

/// Camera maths for a pitch-0 view of the Earth as a sphere.
nonisolated enum GlobeFit {
    static let earthRadius: Double = 6_371_000
    /// How far south of the Jeep the camera looks, so the dot sits above the globe's centre (as in the mockup).
    static let southOffset: Double = 15
    /// The angle of the point measured to learn the view's focal length.
    static let probeAngle: Double = 30 * .pi / 180

    /// The camera's centre for a Jeep at `jeep`: 15° south of it (not past −80°).
    static func cameraCenter(for jeep: CLLocationCoordinate2D?) -> CLLocationCoordinate2D {
        guard let jeep else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        return CLLocationCoordinate2D(latitude: max(-80, jeep.latitude - southOffset), longitude: jeep.longitude)
    }

    /// The probe point: `probeAngle` north of `center` (south when that would pass the pole).
    static func probe(from center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let deg = probeAngle * 180 / .pi
        let lat = center.latitude + deg <= 89 ? center.latitude + deg : center.latitude - deg
        return CLLocationCoordinate2D(latitude: lat, longitude: center.longitude)
    }

    /// The camera distance (above the surface) that draws the globe with screen radius `radius`,
    /// given that at distance `current` the probe point showed `measured` points from the centre.
    /// Nil if the measurement can't be used.
    static func distance(measured: Double, at current: Double, radius: Double) -> Double? {
        let r = earthRadius
        guard measured.isFinite, measured > 1, current > 0, radius > 1 else { return nil }
        // Pinhole: offset = f · R sinθ / (d + R − R cosθ), so the focal length in points is:
        let f = measured * (current + r - r * cos(probeAngle)) / (r * sin(probeAngle))
        // The limb shows at f · tanα with sinα = R / (d + R): solve for d.
        let centreDistance = r * (1 + (f / radius) * (f / radius)).squareRoot()
        let d = centreDistance - r
        guard d.isFinite else { return nil }
        return min(max(d, 2_000_000), 60_000_000)
    }
}

// MARK: - View

/// The whole Earth seen from far out: at night a satellite globe on black (imagery only: no
/// labels or borders); by day Apple Maps' muted day map, blue oceans and land. Seen
/// from far out over the Jeep's last location, with one small blue dot on the Jeep. Picture
/// only: no touches, no compass or scale. Apple's legal label stays (MapKit requires it); the
/// view can be larger than what shows, so `margins` keep the label on the visible part.
struct GlobeView: UIViewRepresentable {
    /// The first camera distance, before the fit.
    static let distance: CLLocationDistance = 22_000_000

    /// The Jeep's location; nil → the camera looks at 0,0 and there's no dot.
    let coordinate: CLLocationCoordinate2D?
    /// The globe's radius on screen, in points.
    var globeRadius: CGFloat = 0
    var margins: EdgeInsets = EdgeInsets()
    var dotSize: CGFloat = 9
    /// CarPlay's appearance: night (satellite) or day (muted standard map).
    var dark: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GlobeMapView {
        let map = GlobeMapView(frame: .zero)
        map.insetsLayoutMarginsFromSafeArea = false

        map.isUserInteractionEnabled = false
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false

        map.delegate = context.coordinator
        updateUIView(map, context: context)
        return map
    }

    func updateUIView(_ map: GlobeMapView, context: Context) {
        let insets = UIEdgeInsets(
            top: margins.top, left: margins.leading, bottom: margins.bottom, right: margins.trailing)
        if map.layoutMargins != insets { map.layoutMargins = insets }
        map.globeRadius = globeRadius
        context.coordinator.style(dark: dark, on: map)
        context.coordinator.show(coordinate, dotSize: dotSize, on: map)
    }

    static func dismantleUIView(_ map: GlobeMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var dot: MKPointAnnotation? = nil
        private var shownKey: [Double]? = nil
        private var shownOnce = false
        private var dotSize: CGFloat = 9
        private var shownDark: Bool? = nil

        /// Night: satellite imagery on black. Day: the muted standard map in its light style.
        /// Only when it changed; the camera is fitted again after.
        func style(dark: Bool, on map: GlobeMapView) {
            guard dark != shownDark else { return }
            shownDark = dark
            if dark {
                map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
                map.overrideUserInterfaceStyle = .dark
                map.backgroundColor = .black
            } else {
                let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
                config.pointOfInterestFilter = .excludingAll
                config.showsTraffic = false
                map.preferredConfiguration = config
                map.overrideUserInterfaceStyle = .light
                map.backgroundColor = .white
            }
            map.refit()
        }

        /// Points the camera and moves the dot, only when something changed. No animation.
        func show(_ coordinate: CLLocationCoordinate2D?, dotSize: CGFloat, on map: GlobeMapView) {
            if dotSize != self.dotSize {
                self.dotSize = dotSize
                if let dot, let view = map.view(for: dot) as? JeepDotView { view.setSize(dotSize) }
            }

            let valid = coordinate.flatMap { CLLocationCoordinate2DIsValid($0) ? $0 : nil }
            let key = valid.map { [$0.latitude, $0.longitude] }
            guard !shownOnce || key != shownKey else { return }
            shownOnce = true
            shownKey = key

            map.globeCenter = GlobeFit.cameraCenter(for: valid)

            if let valid {
                if let dot {
                    dot.coordinate = valid
                } else {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = valid
                    map.addAnnotation(annotation)
                    dot = annotation
                }
            } else if let dot {
                map.removeAnnotation(dot)
                self.dot = nil
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let id = JeepDotView.reuseID
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? JeepDotView)
                ?? JeepDotView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.setSize(dotSize)
            return view
        }
    }
}

/// An `MKMapView` that frames the globe itself: whenever its size, centre or wanted radius
/// changes it sets the camera, measures how big the Earth came out and corrects the distance
/// once. (A camera set before the first layout would otherwise be lost.)
final class GlobeMapView: MKMapView {
    var globeCenter: CLLocationCoordinate2D? {
        didSet { needsFit = true; setNeedsLayout() }
    }

    var globeRadius: CGFloat = 0 {
        didSet { if globeRadius != oldValue { needsFit = true; setNeedsLayout() } }
    }

    private var needsFit = true
    private var fittedSize: CGSize = .zero

    /// Sets the camera again on the next layout (after a change of map configuration).
    func refit() {
        needsFit = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize { needsFit = true }
        guard needsFit, let center = globeCenter, bounds.width > 0, bounds.height > 0 else { return }
        needsFit = false
        fittedSize = bounds.size

        setCamera(makeCamera(center, GlobeView.distance), animated: false)
        guard globeRadius > 0 else { return }
        let current = camera.centerCoordinateDistance
        let p0 = convert(center, toPointTo: self)
        let p1 = convert(GlobeFit.probe(from: center), toPointTo: self)
        let measured = Double(hypot(p1.x - p0.x, p1.y - p0.y))
        if let d = GlobeFit.distance(measured: measured, at: current, radius: Double(globeRadius)) {
            setCamera(makeCamera(center, d), animated: false)
        }
    }

    private func makeCamera(_ center: CLLocationCoordinate2D, _ distance: CLLocationDistance) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: 0)
    }
}

/// The Jeep on the globe: a small blue dot (#0A84FF) in a white ring.
final class JeepDotView: MKAnnotationView {
    static let reuseID = "jeep"

    private let inner = CALayer()
    private var size: CGFloat = 0

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        canShowCallout = false
        isEnabled = false
        displayPriority = .required
        backgroundColor = .white
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
        inner.backgroundColor = UIColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1).cgColor
        layer.addSublayer(inner)
        setSize(9)
    }

    /// Diameter in points; the white ring is about a fifth of it.
    func setSize(_ d: CGFloat) {
        guard d != size else { return }
        size = d
        let ring = max(1.5, (d * 0.2).rounded())
        bounds = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = d / 2
        let i = d - 2 * ring
        inner.frame = CGRect(x: ring, y: ring, width: i, height: i)
        inner.cornerRadius = i / 2
    }
}
