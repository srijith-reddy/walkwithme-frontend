import UIKit
import CoreLocation
import RealityKit
import MapKit

final class ARHUDManager: NSObject {

    static let shared = ARHUDManager()
    private override init() {}

    // UI elements
    private var compassView: UIImageView?
    private var minimapView: MKMapView?
    private var arrowView: UIImageView?

    // Parent
    private weak var parentView: UIView?
    private var isAttached = false

    // Style
    enum MiniMapStyle { case halfBottom, circleRight }
    private var miniMapStyle: MiniMapStyle = .halfBottom

    // Constraints we toggle
    private var miniMapWidthConstraint: NSLayoutConstraint?
    private var miniMapHeightConstraint: NSLayoutConstraint?
    private var miniMapTrailingConstraint: NSLayoutConstraint?
    private var miniMapCenterXConstraint: NSLayoutConstraint?
    private var miniMapBottomConstraint: NSLayoutConstraint?
    private var miniMapTopConstraint: NSLayoutConstraint?
    private var miniMapCenterYConstraint: NSLayoutConstraint?

    private var arrowCenterXConstraint: NSLayoutConstraint?
    private var arrowCenterYConstraint: NSLayoutConstraint?
    private var arrowBottomConstraint: NSLayoutConstraint?

    // Route overlay
    private var routeOverlay: MKPolyline?

    // --------------------------------------------------------
    // Attach HUD to ARView
    // --------------------------------------------------------
    func attach(to view: UIView) {
        guard !isAttached else { return }
        isAttached = true

        parentView = view
        setupCompass(in: view)
        setupMiniMap(in: view)   // default style applied inside
        // No progress bar
    }

    func setMiniMapStyle(_ style: MiniMapStyle) {
        miniMapStyle = style
        applyMiniMapLayout()
    }

    // --------------------------------------------------------
    // COMPASS
    // --------------------------------------------------------
    private func setupCompass(in view: UIView) {
        let img = UIImage(systemName: "location.north.line.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        let iv = UIImageView(image: img)
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.alpha = 0.85

        view.addSubview(iv)
        compassView = iv

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            iv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            iv.widthAnchor.constraint(equalToConstant: 40),
            iv.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    func updateCompass(heading: CLLocationDirection) {
        guard let compassView else { return }
        let radians = CGFloat(heading * .pi / 180)
        UIView.animate(withDuration: 0.15) {
            compassView.transform = CGAffineTransform(rotationAngle: -radians)
        }
    }

    // --------------------------------------------------------
    // LIVE MINIMAP — MKMapView + mask
    // --------------------------------------------------------
    private func setupMiniMap(in view: UIView) {
        let mv = MKMapView()
        mv.translatesAutoresizingMaskIntoConstraints = false
        mv.isUserInteractionEnabled = false
        mv.showsCompass = false
        mv.showsScale = false
        mv.showsPointsOfInterest = true
        mv.isRotateEnabled = true
        mv.isPitchEnabled = false
        mv.delegate = self
        if #available(iOS 16.0, *) {
            mv.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }

        view.addSubview(mv)
        minimapView = mv

        // Size constraints — adjusted by layout method
        miniMapWidthConstraint  = mv.widthAnchor.constraint(equalToConstant: 280)
        miniMapHeightConstraint = mv.heightAnchor.constraint(equalToConstant: 140)

        // Positional constraints; we toggle which ones are active
        miniMapTrailingConstraint = mv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        miniMapCenterXConstraint  = mv.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        miniMapBottomConstraint   = mv.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        miniMapTopConstraint      = mv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        miniMapCenterYConstraint  = mv.centerYAnchor.constraint(equalTo: view.centerYAnchor)

        NSLayoutConstraint.activate([
            miniMapWidthConstraint!, miniMapHeightConstraint!
        ])

        // Arrow overlay (fixed up arrow; map rotates with heading)
        let arrow = UIImageView(image: UIImage(systemName: "location.north.fill")?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal))
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.contentMode = .scaleAspectFit
        mv.addSubview(arrow)
        arrowView = arrow

        // Arrow constraints (will be adjusted per style)
        arrowCenterXConstraint = arrow.centerXAnchor.constraint(equalTo: mv.centerXAnchor)
        arrowCenterYConstraint = arrow.centerYAnchor.constraint(equalTo: mv.centerYAnchor)
        arrowBottomConstraint  = arrow.bottomAnchor.constraint(equalTo: mv.bottomAnchor, constant: -12)

        arrow.widthAnchor.constraint(equalToConstant: 22).isActive = true
        arrow.heightAnchor.constraint(equalToConstant: 22).isActive = true

        applyMiniMapLayout()
    }

    private func applyMiniMapLayout() {
        guard let mv = minimapView, let superV = mv.superview else { return }

        // Deactivate positional constraints
        [miniMapTrailingConstraint, miniMapCenterXConstraint,
         miniMapBottomConstraint, miniMapTopConstraint,
         miniMapCenterYConstraint].forEach { $0?.isActive = false }

        // Deactivate arrow positional constraints
        [arrowCenterXConstraint, arrowCenterYConstraint, arrowBottomConstraint]
            .forEach { $0?.isActive = false }

        switch miniMapStyle {
        case .halfBottom:
            // Big semicircle centered at bottom
            miniMapWidthConstraint?.constant = 280  // diameter
            miniMapHeightConstraint?.constant = 140 // radius
            miniMapCenterXConstraint?.isActive = true
            miniMapBottomConstraint?.constant = -8
            miniMapBottomConstraint?.isActive = true

            // Mask to bottom half circle
            mv.layer.cornerRadius = 0
            mv.layer.mask = halfCircleMask(for: mv.bounds.size)

            // Arrow near bottom-center
            arrowCenterXConstraint?.isActive = true
            arrowBottomConstraint?.constant = -12
            arrowBottomConstraint?.isActive = true

        case .circleRight:
            // Small circle on right side
            miniMapWidthConstraint?.constant = 120
            miniMapHeightConstraint?.constant = 120
            miniMapTrailingConstraint?.constant = -12
            miniMapTrailingConstraint?.isActive = true
            miniMapCenterYConstraint?.isActive = true

            // Perfect circle
            mv.layer.mask = nil
            mv.layer.cornerRadius = 60
            mv.layer.masksToBounds = true

            // Arrow in center
            arrowCenterXConstraint?.isActive = true
            arrowCenterYConstraint?.isActive = true
        }

        // Animate to new spot
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
            superV.layoutIfNeeded()
            // Ensure mask path fits final size
            if self.miniMapStyle == .halfBottom {
                mv.layer.mask = self.halfCircleMask(for: mv.bounds.size)
            }
        }
    }

    private func halfCircleMask(for size: CGSize) -> CALayer {
        let path = UIBezierPath()
        // Semicircle centered at bottom: circle center = (w/2, h), radius = h
        path.addArc(withCenter: CGPoint(x: size.width/2, y: size.height),
                    radius: size.height,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.close()

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        return mask
    }

    // --------------------------------------------------------
    // Called by ARSessionManager on a timer
    // --------------------------------------------------------
    func updateMiniMap(userLocation: CLLocationCoordinate2D,
                       route: Route,
                       heading: CLLocationDirection) {

        guard let mv = minimapView else { return }

        // Update camera: follow user and rotate to heading
        let cam = MKMapCamera(
            lookingAtCenter: userLocation,
            fromDistance: 350,   // tweak for scale
            pitch: 0,
            heading: heading
        )
        mv.setCamera(cam, animated: true)

        // Update route overlay (replace for simplicity)
        if let overlay = routeOverlay {
            mv.removeOverlay(overlay)
            routeOverlay = nil
        }
        let coords = route.coordinatePoints
        if coords.count >= 2 {
            let poly = MKPolyline(coordinates: coords, count: coords.count)
            routeOverlay = poly
            mv.addOverlay(poly)
        }
    }

    // --------------------------------------------------------
    // Progress API (no-op)
    // --------------------------------------------------------
    func updateProgress(percent: Double) {
        // intentionally empty — progress bar removed
    }
}

// ---------------------------------------------------------
// MARK: - MKMapViewDelegate
// ---------------------------------------------------------
extension ARHUDManager: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let poly = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth = 6
            r.lineJoin = .round
            r.lineCap = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
