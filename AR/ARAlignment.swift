import Foundation
import CoreLocation
import simd

/// Converts lat/lon → AR local coordinates using proper ECEF → ENU math.
final class ARAlignment {

    private var origin: CLLocationCoordinate2D?
    private var originECEF = SIMD3<Double>(0,0,0)

    private var east  = SIMD3<Double>(0,0,0)
    private var north = SIMD3<Double>(0,0,0)
    private var up    = SIMD3<Double>(0,0,0)

    // MARK: - RESET EACH SESSION
    func reset() {
        origin = nil
    }

    // MARK: - Set Origin (correct ENU)
    func setOrigin(_ coordinate: CLLocationCoordinate2D) {

        origin = coordinate
        originECEF = ecef(from: coordinate)

        let lat = coordinate.latitude.radians
        let lon = coordinate.longitude.radians

        // TRUE ENU basis vectors
        east  = SIMD3<Double>(-sin(lon),            cos(lon),               0)
        north = SIMD3<Double>(-sin(lat)*cos(lon),  -sin(lat)*sin(lon),     cos(lat))
        up    = SIMD3<Double>( cos(lat)*cos(lon),   cos(lat)*sin(lon),     sin(lat))
    }

    // MARK: - Convert GPS → AR Local Position
    func localPosition(for coord: CLLocationCoordinate2D,
                       relativeTo originCoord: CLLocationCoordinate2D) -> SIMD3<Float> {

        // Origin must be reset per session
        if origin == nil {
            setOrigin(originCoord)
        }

        guard origin != nil else { return SIMD3<Float>(0,0,0) }

        let targetECEF = ecef(from: coord)
        let diff = targetECEF - originECEF

        let e = simd_dot(diff, east)     // X
        let n = simd_dot(diff, north)    // Z (north)
        let u = simd_dot(diff, up)       // Y

        // ARKit:
        // x → east, y → up, z → -north
        return SIMD3<Float>(Float(e), Float(u), Float(-n))
    }

    // MARK: - ECEF Conversion
    private func ecef(from coord: CLLocationCoordinate2D) -> SIMD3<Double> {

        let lat = coord.latitude.radians
        let lon = coord.longitude.radians

        // WGS84
        let a = 6378137.0
        let f = 1/298.257223563
        let e2 = f * (2 - f)

        let sinLat = sin(lat)
        let cosLat = cos(lat)
        let sinLon = sin(lon)
        let cosLon = cos(lon)

        let N = a / sqrt(1 - e2 * sinLat * sinLat)

        // altitude = 0 (fine for roads)
        let h = 0.0

        let x = (N + h) * cosLat * cosLon
        let y = (N + h) * cosLat * sinLon
        let z = (N * (1 - e2) + h) * sinLat

        return SIMD3<Double>(x, y, z)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}
