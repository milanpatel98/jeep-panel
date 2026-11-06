import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Camera (pure, tested)

/// Where the map looks when Earth opens: over the Jeep, from a neighbourhood's height.
nonisolated enum JeepMapCamera {
    /// Metres above the ground.
    static let distance: CLLocationDistance = 2_400

    /// The map's centre: the Jeep, or nowhere in particular (0, 0, far out) without a fix.
    static func center(for jeep: CLLocationCoordinate2D?) -> (CLLocationCoordinate2D, CLLocationDistance) {
        guard let jeep, CLLocationCoordinate2DIsValid(jeep) else {
            return (CLLocationCoordinate2D(latitude: 20, longitude: 0), 20_000_000)
        }
        return (jeep, distance)
    }
}

// MARK: - View

/// Apple Maps' own look (the standard map, its realistic elevation, night or day with CarPlay),
/// centred on the Jeep's last location with a small blue dot on it. Picture only: no touches, no
/// compass or scale. Apple's legal label stays (MapKit requires it).
struct JeepMapView: UIViewRepresentable {
    /// The Jeep's location; nil → far out over the Atlantic and no dot.
    let coordinate: CLLocationCoordinate2D?
    var dotSize: CGFloat = 10
    /// CarPlay's appearance: night or day.
    var dark: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
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

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.style(dark: dark, on: map)
        context.coordinator.show(coordinate, dotSize: dotSize, on: map)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var dot: MKPointAnnotation? = nil
        private var shownKey: [Double]? = nil
        private var shownOnce = false
        private var dotSize: CGFloat = 10
        private var shownDark: Bool? = nil

        /// Only when it changed.
        func style(dark: Bool, on map: MKMapView) {
            guard dark != shownDark else { return }
            shownDark = dark
            let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
            config.showsTraffic = false
            map.preferredConfiguration = config
            map.overrideUserInterfaceStyle = dark ? .dark : .light
            map.backgroundColor = dark ? .black : UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
        }

        /// Points the camera and moves the dot, only when something changed. No animation.
        func show(_ coordinate: CLLocationCoordinate2D?, dotSize: CGFloat, on map: MKMapView) {
            if dotSize != self.dotSize {
                self.dotSize = dotSize
                if let dot, let view = map.view(for: dot) as? JeepDotView { view.setSize(dotSize) }
            }

            let valid = coordinate.flatMap { CLLocationCoordinate2DIsValid($0) ? $0 : nil }
            let key = valid.map { [$0.latitude, $0.longitude] }
            guard !shownOnce || key != shownKey else { return }
            shownOnce = true
            shownKey = key

            let (center, distance) = JeepMapCamera.center(for: valid)
            map.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: 0), animated: false)

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

/// The Jeep on the map: a small blue dot (#0A84FF) in a white ring.
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
        setSize(10)
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
