import XCTest
@testable import VoltIQ

@MainActor private final class MockLocation: LocationProviding {
    var authorization: LocationAuthorization
    var grantOnRequest: Bool
    var result: Result<Coordinate, Error>
    private(set) var requests = 0
    init(_ auth: LocationAuthorization = .authorized, grant: Bool = true, result: Result<Coordinate, Error> = .success(Coordinate(latitude: 17.4435, longitude: 78.3772))) {
        authorization = auth; grantOnRequest = grant; self.result = result
    }
    func requestAuthorization() async -> LocationAuthorization {
        requests += 1
        authorization = grantOnRequest ? .authorized : .denied
        return authorization
    }
    func currentLocation() async throws -> Coordinate { try result.get() }
}

private final class MockProvider: ChargerProvider {
    var result: Result<[RawStation], Error>
    private(set) var lastLocation: Coordinate?
    private(set) var lastConfig: ChargerDiscoveryConfig?
    private(set) var calls = 0
    init(_ result: Result<[RawStation], Error> = .success([])) { self.result = result }
    func search(near location: Coordinate, config: ChargerDiscoveryConfig) async throws -> [RawStation] {
        calls += 1; lastLocation = location; lastConfig = config
        return try result.get()
    }
}

private func raw(_ id: String?, _ name: String? = "Station", lat: Double? = 17.45, lon: Double? = 78.38, address: String? = "Hitech City") -> RawStation {
    RawStation(id: id, name: name, latitude: lat, longitude: lon, address: address, source: "mock")
}

@MainActor
final class ChargerDiscoveryTests: XCTestCase {
    private func model(_ location: MockLocation? = nil, _ provider: MockProvider = MockProvider(), config: ChargerDiscoveryConfig = .default) -> ChargerDiscoveryViewModel {
        ChargerDiscoveryViewModel(location: location ?? MockLocation(), provider: provider, config: config)
    }

    func testPermissionGrantedOnFirstUseLoadsStations() async {
        let location = MockLocation(.notDetermined)
        let vm = model(location, MockProvider(.success([raw("a")])))
        await vm.load()
        XCTAssertEqual(location.requests, 1)
        XCTAssertEqual(vm.stations.map(\.id), ["a"])
    }

    func testPermissionDeniedStopsLoadingAndDoesNotRepromptOnLoad() async {
        let location = MockLocation(.notDetermined, grant: false)
        let provider = MockProvider()
        let vm = model(location, provider)
        await vm.load()
        XCTAssertEqual(vm.state, .permissionDenied)
        XCTAssertFalse(vm.state.isLoading)
        await vm.load()
        XCTAssertEqual(location.requests, 1)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertNil(vm.userLocation)
    }

    func testRetryAfterGrantingInSettingsRecovers() async {
        let location = MockLocation(.denied)
        let vm = model(location, MockProvider(.success([raw("a")])))
        await vm.load()
        XCTAssertEqual(vm.state, .permissionDenied)
        location.authorization = .authorized
        await vm.retry()
        XCTAssertEqual(vm.stations.count, 1)
    }

    func testUserLocationAndConfigArePassedToProvider() async {
        let here = Coordinate(latitude: 12.97, longitude: 77.59)
        let provider = MockProvider(.success([raw("a")]))
        let vm = model(MockLocation(result: .success(here)), provider, config: ChargerDiscoveryConfig(radiusMeters: 1234, resultLimit: 3))
        await vm.load()
        XCTAssertEqual(provider.lastLocation, here)
        XCTAssertEqual(provider.lastConfig, ChargerDiscoveryConfig(radiusMeters: 1234, resultLimit: 3))
        XCTAssertEqual(vm.userLocation, here)
        XCTAssertEqual(ChargerDiscoveryConfig.default, ChargerDiscoveryConfig(radiusMeters: 5000, resultLimit: 20))
    }

    func testMultipleStationsSortedNearestFirstWithDistances() async {
        let vm = model(MockLocation(result: .success(Coordinate(latitude: 17.0, longitude: 78.0))),
                       MockProvider(.success([raw("far", lat: 17.05, lon: 78.0), raw("near", lat: 17.01, lon: 78.0), raw("mid", lat: 17.02, lon: 78.0)])))
        await vm.load()
        XCTAssertEqual(vm.stations.map(\.id), ["near", "mid", "far"])
        XCTAssertEqual(vm.stations[0].distanceMeters ?? 0, 1112, accuracy: 15)
        XCTAssertEqual(vm.stations[0].distanceText, "1.1 km away")
    }

    func testSingleStation() async {
        let vm = model(MockLocation(), MockProvider(.success([raw("only")])))
        await vm.load()
        XCTAssertEqual(vm.state, .loaded(vm.stations))
        XCTAssertEqual(vm.stations.count, 1)
    }

    func testZeroStationsIsEmptyNotError() async {
        let vm = model(MockLocation(), MockProvider(.success([])))
        await vm.load()
        XCTAssertEqual(vm.state, .empty)
    }

    func testDuplicateIdsProduceOneStation() async {
        let vm = model(MockLocation(), MockProvider(.success([raw("a"), raw("a", "Dup"), raw("b")])))
        await vm.load()
        XCTAssertEqual(vm.stations.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(Set(vm.stations.map(\.id)).count, vm.stations.count)
    }

    func testMissingAddressAndNameAreNotRenderedAsNullText() {
        let stations = StationNormalizer.normalize([raw("a", "  ", address: nil), raw("b", "X", address: "null"), raw("c", "Y", address: "")], from: nil, limit: 20)
        XCTAssertEqual(stations.count, 3)
        XCTAssertTrue(stations.allSatisfy { $0.address == nil })
        XCTAssertEqual(stations.first { $0.id == "a" }?.name, "EV charging station")
    }

    func testInvalidCoordinatesAreDroppedAndDistanceNotInvented() {
        let list = [raw("nolat", lat: nil), raw("nolon", lon: nil), raw("nan", lat: .nan), raw("range", lat: 91), raw(nil), raw("ok")]
        XCTAssertEqual(StationNormalizer.normalize(list, from: Coordinate(latitude: 17, longitude: 78), limit: 20).map(\.id), ["ok"])
        let noUser = StationNormalizer.normalize([raw("ok")], from: nil, limit: 20)
        XCTAssertNil(noUser[0].distanceMeters)
        XCTAssertNil(noUser[0].distanceText)
    }

    func testResultLimitApplied() {
        let list = (0..<30).map { raw("s\($0)", lat: 17 + Double($0) / 1000) }
        XCTAssertEqual(StationNormalizer.normalize(list, from: Coordinate(latitude: 17, longitude: 78), limit: 20).count, 20)
    }

    func testProviderFailuresShowSafeMessageAndRetryRecovers() async {
        struct Secret: Error, LocalizedError { var errorDescription: String? { "key=ABC123 stack trace" } }
        let provider = MockProvider(.failure(Secret()))
        let vm = model(MockLocation(), provider)
        await vm.load()
        guard case .failed(let text) = vm.state else { return XCTFail("expected failure") }
        XCTAssertFalse(text.contains("ABC123"))
        XCTAssertFalse(vm.state.isLoading)
        provider.result = .failure(URLError(.notConnectedToInternet))
        await vm.retry()
        XCTAssertEqual(vm.state, .failed(ChargerDiscoveryError.network.userMessage))
        provider.result = .failure(ChargerDiscoveryError.timeout)
        await vm.retry()
        XCTAssertEqual(vm.state, .failed(ChargerDiscoveryError.timeout.userMessage))
        provider.result = .success([raw("a")])
        await vm.retry()
        XCTAssertEqual(vm.stations.count, 1)
    }

    func testLocationFailureIsReportedNotLoadingForever() async {
        let vm = model(MockLocation(result: .failure(ChargerDiscoveryError.timeout)), MockProvider())
        await vm.load()
        XCTAssertEqual(vm.state, .failed(ChargerDiscoveryError.timeout.userMessage))
    }

    func testInvalidUserLocationIsRejected() async {
        let provider = MockProvider()
        let vm = model(MockLocation(result: .success(Coordinate(latitude: .nan, longitude: 0))), provider)
        await vm.load()
        XCTAssertEqual(vm.state, .failed(ChargerDiscoveryError.locationUnavailable.userMessage))
        XCTAssertEqual(provider.calls, 0)
    }

    func testListMappingFormatsDistance() {
        let near = ChargingStation(id: "a", name: "A", latitude: 0, longitude: 0, address: nil, distanceMeters: 450.4, source: "mock")
        let far = ChargingStation(id: "b", name: "B", latitude: 0, longitude: 0, address: nil, distanceMeters: 2400, source: "mock")
        XCTAssertEqual(near.distanceText, "450 m away")
        XCTAssertEqual(far.distanceText, "2.4 km away")
    }

    func testMapAndListSelectionShareOneStationId() async {
        let vm = model(MockLocation(), MockProvider(.success([raw("a"), raw("b", lat: 17.5)])))
        await vm.load()
        vm.select(id: "b")
        XCTAssertEqual(vm.selectedStation?.id, "b")
        vm.select(id: "a")
        XCTAssertEqual(vm.selectedStation?.id, "a")
        vm.select(id: "unknown")
        XCTAssertEqual(vm.selectedID, "a")
        vm.select(id: nil)
        XCTAssertNil(vm.selectedStation)
    }

    func testRepeatedLoadWhileLoadingIsIgnored() async {
        let provider = MockProvider(.success([raw("a")]))
        let vm = model(MockLocation(), provider)
        async let first: Void = vm.load()
        async let second: Void = vm.load()
        _ = await (first, second)
        XCTAssertEqual(vm.stations.count, 1)
        XCTAssertLessThanOrEqual(provider.calls, 2)
    }
}
