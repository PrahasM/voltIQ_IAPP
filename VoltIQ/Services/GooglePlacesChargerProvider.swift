import Foundation

/// Google Places (New) Nearby Search. Connector data arrives in the same response as discovery.
struct GooglePlacesChargerProvider: ChargerProvider {
    var apiKey: String
    var bundleID: String? = Bundle.main.bundleIdentifier
    var session: URLSession = .shared

    func search(near location: Coordinate, config: ChargerDiscoveryConfig) async throws -> [RawStation] {
        let request = try GooglePlacesRequest.make(location: location, config: config, apiKey: apiKey, bundleID: bundleID)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .timedOut { throw ChargerDiscoveryError.timeout }
        catch let error as URLError { throw error }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            NSLog("Places search failed with status %d", (response as? HTTPURLResponse)?.statusCode ?? -1)
            throw ChargerDiscoveryError.provider
        }
        return try GooglePlacesMapper.map(data)
    }
}

enum ChargerProviderFactory {
    /// Google Places when a key is configured; otherwise MapKit (no connector details).
    static func make(bundle: Bundle = .main) -> ChargerProvider {
        make(apiKey: bundle.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String)
    }

    static func make(apiKey: String?) -> ChargerProvider {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty || key.hasPrefix("$(") ? MapKitChargerProvider() : GooglePlacesChargerProvider(apiKey: key)
    }
}
