import UIKit
import CoreLocation
import RealityKit

final class ARHUDManager {

    static let shared = ARHUDManager()
    private init() {}

    // UI elements
    private var compassView: UIImageView?
    private var minimapView: UIImageView?
    private var progressBar: UIProgressView?

    private weak var parentView: UIView?

    // --------------------------------------------------------
    // Attach HUD to ARView
    // --------------------------------------------------------
    func attach(to view: UIView) {
        parentView = view
        setupCompass(in: view)
        setupMiniMap(in: view)
        setupProgress(in: view)
    }

    // --------------------------------------------------------
    // COMPASS
    // --------------------------------------------------------
    private func setupCompass(in view: UIView) {
        let img = UIImage(systemName: "location.north.line.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        let iv = UIImageView(image: img)
        iv.frame = CGRect(x: 20, y: 20, width: 40, height: 40)
        iv.alpha = 0.85

        view.addSubview(iv)
        compassView = iv
    }

    func updateCompass(heading: CLLocationDirection) {
        guard let compassView else { return }

        let radians = CGFloat(heading * .pi / 180)
        UIView.animate(withDuration: 0.15) {
            compassView.transform = CGAffineTransform(rotationAngle: -radians)
        }
    }

    // --------------------------------------------------------
    // MINIMAP SETUP
    // --------------------------------------------------------
    private func setupMiniMap(in view: UIView) {
        let iv = UIImageView()
        iv.frame = CGRect(x: view.bounds.width - 140,
                          y: 20,
                          width: 120,
                          height: 120)

        iv.layer.cornerRadius = 60
        iv.layer.masksToBounds = true
        iv.alpha = 0.85
        iv.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        view.addSubview(iv)
        minimapView = iv
    }

    // --------------------------------------------------------
    // UTIL — Distance between coords
    // --------------------------------------------------------
    private func distance(_ a: CLLocationCoordinate2D,
                          _ b: CLLocationCoordinate2D) -> Double {

        let l1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let l2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return l1.distance(from: l2)
    }

    // --------------------------------------------------------
    // UTIL — Get next ~100m of route
    // --------------------------------------------------------
    private func sliceRoute(_ coords: [CLLocationCoordinate2D],
                            from user: CLLocationCoordinate2D,
                            maxDistance: Double = 100) -> [CLLocationCoordinate2D] {

        var sliced: [CLLocationCoordinate2D] = [user]
        var total = 0.0
        var last = user

        for c in coords {
            let d = distance(last, c)
            total += d
            if total > maxDistance { break }
            sliced.append(c)
            last = c
        }

        return sliced
    }

    // --------------------------------------------------------
    // UPDATE MINIMAP (true 50–100m slice)
    // --------------------------------------------------------
    func updateMiniMap(userLocation: CLLocationCoordinate2D,
                       route: Route,
                       heading: CLLocationDirection) {

        guard let minimapView else { return }

        let size = CGSize(width: 120, height: 120)

        // Convert backend [lat, lon] → CLLocationCoordinate2D
        let coords = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])
        }

        // Slice next ~100 m of route from user's real location
        let sliced = sliceRoute(coords, from: userLocation, maxDistance: 100)

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        ctx.setFillColor(UIColor.clear.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // ----------------------------------------------
        // ROTATE minimap for heading
        // ----------------------------------------------
        let rad = CGFloat(heading * .pi / 180)
        ctx.translateBy(x: size.width/2, y: size.height/2)
        ctx.rotate(by: -rad)
        ctx.translateBy(x: -size.width/2, y: -size.height/2)

        // ----------------------------------------------
        // MAP POINT FUNCTION (center = userLocation)
        // ----------------------------------------------
        let scale: CGFloat = 0.6

        func mapPoint(_ c: CLLocationCoordinate2D) -> CGPoint {
            let dx = (c.longitude - userLocation.longitude) * 80000
            let dy = (c.latitude - userLocation.latitude) * 80000

            return CGPoint(
                x: size.width/2 + CGFloat(dx) * scale,
                y: size.height/2 - CGFloat(dy) * scale
            )
        }

        // ----------------------------------------------
        // DRAW ROUTE SLICE
        // ----------------------------------------------
        if sliced.count >= 2 {
            ctx.setLineWidth(4)
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)

            ctx.beginPath()
            for (i, c) in sliced.enumerated() {
                let p = mapPoint(c)
                if i == 0 { ctx.move(to: p) }
                else { ctx.addLine(to: p) }
            }
            ctx.strokePath()
        }

        // ----------------------------------------------
        // USER ARROW (always in center)
        // ----------------------------------------------
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: size.width/2, y: size.height/2 - 8))
        ctx.addLine(to: CGPoint(x: size.width/2 - 6, y: size.height/2 + 6))
        ctx.addLine(to: CGPoint(x: size.width/2 + 6, y: size.height/2 + 6))
        ctx.closePath()
        ctx.fillPath()

        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        minimapView.image = img
    }

    // --------------------------------------------------------
    // PROGRESS BAR
    // --------------------------------------------------------
    private func setupProgress(in view: UIView) {
        let bar = UIProgressView(progressViewStyle: .default)

        bar.frame = CGRect(
            x: 40,
            y: view.bounds.height - 40,
            width: view.bounds.width - 80,
            height: 20
        )

        bar.progressTintColor = .systemGreen
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        bar.layer.cornerRadius = 4
        bar.clipsToBounds = true
        bar.alpha = 0.9

        view.addSubview(bar)
        progressBar = bar
    }

    func updateProgress(percent: Double) {
        guard let progressBar else { return }

        let p = max(0, min(1, percent))
        progressBar.setProgress(Float(p), animated: true)

        // Color gradient: green → yellow → red
        if p > 0.66 {
            progressBar.progressTintColor = .systemGreen
        } else if p > 0.33 {
            progressBar.progressTintColor = .systemYellow
        } else {
            progressBar.progressTintColor = .systemRed
        }
    }
}
