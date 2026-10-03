import CoreLocation
import MapKit

struct MapKitRouteProvider: RouteProviding {
    func route(from origin: Coordinate, to destination: Coordinate) async throws -> RouteSummary {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)))
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw RouteError.noRoute }
            return Self.summary(route)
        } catch let error as RouteError {
            throw error
        } catch let error as MKError where error.code == .directionsNotFound {
            throw RouteError.noRoute
        } catch let error as URLError {
            throw error
        } catch {
            NSLog("Route request failed: %@", String(describing: error))
            throw RouteError.provider
        }
    }

    static func summary(_ route: MKRoute) -> RouteSummary {
        let count = route.polyline.pointCount
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
        let steps = route.steps.filter { !$0.instructions.isEmpty }.enumerated()
            .map { RouteStep(id: $0.offset, instruction: $0.element.instructions, distanceMeters: $0.element.distance) }
        return RouteSummary(distanceMeters: route.distance, travelSeconds: route.expectedTravelTime,
                            path: coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }, steps: steps)
    }
}
