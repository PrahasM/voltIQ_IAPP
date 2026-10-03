import CoreLocation

/// When-in-use location only; no background or "Always" access is requested.
@MainActor
final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<LocationAuthorization, Never>?
    private var locationContinuation: CheckedContinuation<Coordinate, Error>?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: LocationAuthorization { Self.map(manager.authorizationStatus) }

    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> Coordinate {
        guard locationContinuation == nil else { throw ChargerDiscoveryError.locationUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            Task { [weak self, timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finishLocation(.failure(ChargerDiscoveryError.timeout))
            }
        }
    }

    private func finishLocation(_ result: Result<Coordinate, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }

    nonisolated private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        default: return .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            guard status != .notDetermined, let continuation = self.authContinuation else { return }
            self.authContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.finishLocation(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(.failure(ChargerDiscoveryError.locationUnavailable)) }
    }
}
