import MapKit

extension Route {
    var destinationItem: MKMapItem? {
        guard let last = coordinatePoints.last else { return nil }
        let placemark = MKPlacemark(coordinate: last)
        let item = MKMapItem(placemark: placemark)
        item.name = "Destination"
        return item
    }
}
