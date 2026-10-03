import CoreLocation
import MapKit

/// Apple MapKit EV-charger points of interest. UI code only sees `RawStation`/`ChargingStation`.
struct MapKitChargerProvider: ChargerProvider {
    static let sourceID = "mapkit"

    func search(near location: Coordinate, config: ChargerDiscoveryConfig) async throws -> [RawStation] {
        let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: config.radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.evCharger])
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map(Self.raw)
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch let error as URLError {
            throw error
        } catch let error as MKError where error.code == .serverFailure || error.code == .loadingThrottled {
            throw ChargerDiscoveryError.provider
        } catch {
            NSLog("Charger search failed: %@", String(describing: error))
            throw ChargerDiscoveryError.provider
        }
    }

    // MKMapItem.identifier needs iOS 18, so build a deterministic id from name and rounded coordinate.
    static func raw(_ item: MKMapItem) -> RawStation {
        let c = item.placemark.coordinate
        let name = item.name
        let id = String(format: "mapkit:%@:%.5f,%.5f", name ?? "", c.latitude, c.longitude)
        let address = [item.placemark.thoroughfare, item.placemark.subLocality, item.placemark.locality]
            .compactMap { $0 }.joined(separator: ", ")
        return RawStation(id: id, name: name, latitude: c.latitude, longitude: c.longitude, address: address, source: sourceID)
    }
}
