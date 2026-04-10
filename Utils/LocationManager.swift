import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var lastLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var speed: CLLocationSpeed?        // <-- NEW ✔

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5.0       // meters
        manager.headingFilter = 5.0        // degrees
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // Start Updates only when authorized
    private func startUpdates() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func start() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdates()
        default:
            requestPermission()
        }
    }

    func stop() {
        stopUpdates()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdates()

        case .denied, .restricted:
            stopUpdates()

        case .notDetermined:
            // Let the OS show the prompt
            break

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {

        guard let loc = locations.last else { return }

        lastLocation = loc
        userLocation = loc.coordinate

        // Update speed (ignore -1 which means "invalid")
        if loc.speed >= 0 {
            speed = loc.speed       // m/s
        } else {
            speed = nil
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
}
