import Foundation

enum GooglePlacesRequest {
    static let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    /// Only the fields US-02 needs; deliberately excludes availability and pricing data.
    static let fieldMask = "places.id,places.displayName,places.location,places.formattedAddress,places.evChargeOptions"

    static func make(location: Coordinate, config: ChargerDiscoveryConfig, apiKey: String, bundleID: String?) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("$(") else { throw ChargerDiscoveryError.provider }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        if let bundleID { request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        let body: [String: Any] = [
            "includedTypes": ["electric_vehicle_charging_station"],
            "maxResultCount": min(max(config.resultLimit, 1), 20),
            "rankPreference": "DISTANCE",
            "locationRestriction": ["circle": [
                "center": ["latitude": location.latitude, "longitude": location.longitude],
                "radius": min(max(config.radiusMeters, 1), 50_000)]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}

enum GooglePlacesMapper {
    static let sourceID = "google_places"

    /// Maps a searchNearby response. A malformed connector block only makes that station's connectors nil.
    static func map(_ data: Data) throws -> [RawStation] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ChargerDiscoveryError.provider }
        guard let places = root["places"] else { return [] }   // Places omits the key when nothing matches
        guard let list = places as? [[String: Any]] else { throw ChargerDiscoveryError.provider }
        return list.map { place in
            let location = place["location"] as? [String: Any]
            let name = (place["displayName"] as? [String: Any])?["text"] as? String
            return RawStation(id: place["id"] as? String, name: name,
                              latitude: number(location?["latitude"]), longitude: number(location?["longitude"]),
                              address: place["formattedAddress"] as? String, source: sourceID,
                              connectors: connectors(place["evChargeOptions"]))
        }
    }

    static func connectorType(_ value: String?) -> ConnectorType {
        switch value {
        case "EV_CONNECTOR_TYPE_CCS_COMBO_2": return .ccs2
        case "EV_CONNECTOR_TYPE_CCS_COMBO_1": return .ccs1
        case "EV_CONNECTOR_TYPE_TYPE_2": return .type2
        case "EV_CONNECTOR_TYPE_CHADEMO": return .chademo
        case "EV_CONNECTOR_TYPE_TESLA": return .nacs
        case "EV_CONNECTOR_TYPE_J1772", "EV_CONNECTOR_TYPE_UNSPECIFIED_GB_T", "EV_CONNECTOR_TYPE_UNSPECIFIED_WALL_OUTLET", "EV_CONNECTOR_TYPE_OTHER": return .other
        default: return .unknown
        }
    }

    // availableCount / outOfServiceCount are deliberately never read (US-03).
    private static func connectors(_ options: Any?) -> [RawConnector]? {
        guard let options = options as? [String: Any], let groups = options["connectorAggregation"] as? [Any] else { return nil }
        var result: [RawConnector] = []
        for case let group as [String: Any] in groups {
            result.append(RawConnector(type: connectorType(group["type"] as? String),
                                       maxPowerKW: number(group["maxChargeRateKw"]),
                                       count: number(group["count"]).flatMap { $0.isFinite && $0 == $0.rounded() ? Int($0) : nil }))
        }
        return result.isEmpty ? nil : result
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.doubleValue }
        return nil
    }
}
