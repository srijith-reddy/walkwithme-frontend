import Foundation
import CoreLocation
import simd

/// Converts GPS (lat/lon) to ARKit local coordinates using ECEF → ENU mathematics.
/// Needed for placing anchors in the real-world direction.
final class ARAlignment {

    /// The origin of the AR coordinate system (usually user’s location when AR session starts)
    private var origin: CLLocationCoordinate2D?

    /// ECEF position of the origin
    private var originECEF = SIMD3<Double>(0,0,0)

    /// Local ENU axes (East, North, Up)
    private var east = SIMD3<Double>(0,0,0)
    private var north = SIMD3<Double>(0,0,0)
    private var up = SIMD3<Double>(0,0,0)

    // MARK: - Initialize Origin

    /// Call only once: when AR first sees user’s GPS location.
    func setOrigin(_ coordinate: CLLocationCoordinate2D) {
        guard origin == nil else { return }  // only set once

        origin = coordinate
        originECEF = ecef(from: coordinate)

        // Build ENU basis vectors
        let lat = coordinate.latitude.radians
        let lon = coordinate.longitude.radians

        // ENU unit vectors
        east  = SIMD3<Double>( -sin(lon),  cos(lon), 0 )
        north = SIMD3<Double>( -sin(lat)*cos(lon),
                               -sin(lat)*sin(lon),
                                cos(lat) )
        up    = SIMD3<Double>(  cos(lat)*cos(lon),
                                cos(lat)*sin(lon),
                                sin(lat) )
    }

    // MARK: - Public: Convert GPS → local AR position

    /// Gives ARKit local coordinates for a GPS coordinate relative to origin.
    func localPosition(for coord: CLLocationCoordinate2D,
                       relativeTo originCoord: CLLocationCoordinate2D) -> SIMD3<Float> {

        // Ensure origin is locked
        if origin == nil {
            setOrigin(originCoord)
        }

        guard let origin else {
            return SIMD3<Float>(0, 0, 0)
        }

        // Compute using the locked origin
        let targetECEF = ecef(from: coord)
        let diff = targetECEF - originECEF   // vector from origin → target (ECEF)

        // Project into ENU axes
        let eastVal  = simd_dot(diff, east)
        let northVal = simd_dot(diff, north)
        let upVal    = simd_dot(diff, up)

        // Convert meters (Double) → ARKit Float
        return SIMD3<Float>(Float(eastVal), Float(upVal), Float(-northVal))
        //             X → East,   Y → Up,   Z → South (ARKit forward)
    }

    // MARK: - ECEF Conversion

    /// Converts a GPS coordinate to ECEF XYZ in meters.
    private func ecef(from coord: CLLocationCoordinate2D) -> SIMD3<Double> {

        let lat = coord.latitude.radians
        let lon = coord.longitude.radians

        // WGS84 Ellipsoid constants
        let a = 6378137.0        // major axis
        let f = 1 / 298.257223563
        let e2 = f * (2 - f)

        let sinLat = sin(lat)
        let cosLat = cos(lat)
        let sinLon = sin(lon)
        let cosLon = cos(lon)

        let N = a / sqrt(1 - e2 * sinLat * sinLat)

        let x = (N + 0) * cosLat * cosLon
        let y = (N + 0) * cosLat * sinLon
        let z = (N * (1 - e2)) * sinLat

        return SIMD3<Double>(x, y, z)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}
