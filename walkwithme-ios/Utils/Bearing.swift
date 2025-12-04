import CoreLocation

/// Computes bearing (degrees) from point A → B
/// 0° = North, 90° = East (same convention as CLLocationDirection)
func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
    let lat1 = from.latitude.radians
    let lon1 = from.longitude.radians
    let lat2 = to.latitude.radians
    let lon2 = to.longitude.radians

    let dLon = lon2 - lon1

    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let radiansBearing = atan2(y, x)

    var degrees = radiansBearing.degrees
    if degrees < 0 { degrees += 360 }
    return degrees
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
