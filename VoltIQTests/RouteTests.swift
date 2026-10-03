import XCTest
@testable import VoltIQ

private final class MockRouter: RouteProviding {
    var result: Result<RouteSummary, Error>
    private(set) var calls: [(Coordinate, Coordinate)] = []
    init(_ result: Result<RouteSummary, Error>) { self.result = result }
    func route(from origin: Coordinate, to destination: Coordinate) async throws -> RouteSummary {
        calls.append((origin, destination))
        try await Task.sleep(nanoseconds: 1_000_000)
        return try result.get()
    }
}

@MainActor
final class RouteTests: XCTestCase {
    private let here = Coordinate(latitude: 17.4, longitude: 78.3)
    private let there = Coordinate(latitude: 17.5, longitude: 78.4)
    private let summary = RouteSummary(distanceMeters: 6400, travelSeconds: 720, path: [Coordinate(latitude: 17.4, longitude: 78.3), Coordinate(latitude: 17.5, longitude: 78.4)],
                                       steps: [RouteStep(id: 0, instruction: "Head north", distanceMeters: 300)])

    func testValidOriginLoadsRouteWithExactEndpoints() async {
        let router = MockRouter(.success(summary))
        let vm = RouteViewModel(provider: router, origin: here, destination: there)
        await vm.load()
        XCTAssertEqual(vm.state, .loaded(summary))
        XCTAssertEqual(router.calls.count, 1)
        XCTAssertEqual(router.calls[0].0, here)
        XCTAssertEqual(router.calls[0].1, there)
    }

    func testMissingOrInvalidOriginNeedsLocationAndNeverRoutes() async {
        for origin in [nil, Coordinate(latitude: .nan, longitude: 0), Coordinate(latitude: 95, longitude: 0)] as [Coordinate?] {
            let router = MockRouter(.success(summary))
            let vm = RouteViewModel(provider: router, origin: origin, destination: there)
            await vm.load()
            XCTAssertEqual(vm.state, .needsLocation)
            XCTAssertTrue(router.calls.isEmpty)
        }
    }

    func testNoRouteIsDistinctFromFailureAndRetryRecovers() async {
        let router = MockRouter(.failure(RouteError.noRoute))
        let vm = RouteViewModel(provider: router, origin: here, destination: there)
        await vm.load()
        XCTAssertEqual(vm.state, .noRoute)
        struct Leak: Error, LocalizedError { var errorDescription: String? { "secret internals" } }
        router.result = .failure(Leak())
        await vm.load()
        guard case .failed(let text) = vm.state else { return XCTFail("expected failure") }
        XCTAssertFalse(text.contains("secret"))
        router.result = .failure(URLError(.notConnectedToInternet))
        await vm.load()
        XCTAssertEqual(vm.state, .failed("You appear to be offline. Check your connection and try again."))
        router.result = .success(summary)
        await vm.load()
        XCTAssertEqual(vm.state, .loaded(summary))
    }

    func testConcurrentLoadsMakeOneRequest() async {
        let router = MockRouter(.success(summary))
        let vm = RouteViewModel(provider: router, origin: here, destination: there)
        async let a: Void = vm.load()
        async let b: Void = vm.load()
        _ = await (a, b)
        XCTAssertEqual(router.calls.count, 1)
    }

    func testFormatting() {
        XCTAssertEqual(RouteFormatting.duration(20), "Under 1 min")
        XCTAssertEqual(RouteFormatting.duration(720), "12 min")
        XCTAssertEqual(RouteFormatting.duration(3600), "1 hr")
        XCTAssertEqual(RouteFormatting.duration(5400), "1 hr 30 min")
        XCTAssertEqual(RouteFormatting.distance(240), "240 m")
        XCTAssertEqual(RouteFormatting.distance(6400), "6.4 km")
        XCTAssertEqual(summary.summaryText, "12 min · 6.4 km")
    }
}
