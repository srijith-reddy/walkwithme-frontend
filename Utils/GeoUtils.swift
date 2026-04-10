import CoreLocation

/// Keep every `step`-th coordinate, always preserving first and last.
/// If step <= 1 or the array is short, returns the original array.
func downsample(_ coords: [CLLocationCoordinate2D], step: Int) -> [CLLocationCoordinate2D] {
    guard step > 1, coords.count > 2 else { return coords }
    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity((coords.count / step) + 2)

    for (i, c) in coords.enumerated() {
        if i == 0 || i == coords.count - 1 || i % step == 0 {
            result.append(c)
        }
    }

    // Ensure last is included (in case length-1 wasn’t a multiple of step)
    if let last = coords.last, !coordinatesEqual(result.last, last) {
        result.append(last)
    }
    return result
}

/// Great-circle distance in meters between two coordinates (uses CoreLocation).
func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let l1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
    let l2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
    return l1.distance(from: l2)
}

/// Exact component-wise comparison for CLLocationCoordinate2D
private func coordinatesEqual(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
    guard let a = a else { return false }
    return a.latitude == b.latitude && a.longitude == b.longitude
}
