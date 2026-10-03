import XCTest
@testable import VoltIQ

final class ConnectorDetailsTests: XCTestCase {
    private func place(_ id: String, aggregation: String? = nil, extra: String = "") -> String {
        let evOptions = aggregation.map { #","evChargeOptions":{"connectorCount":9,"connectorAggregation":\#($0)}"# } ?? ""
        return #"{"id":"\#(id)","displayName":{"text":"Station \#(id)"},"formattedAddress":"Hitech City","location":{"latitude":17.45,"longitude":78.38}\#(evOptions)\#(extra)}"#
    }
    private func response(_ places: [String]) -> Data { Data(#"{"places":[\#(places.joined(separator: ","))]}"#.utf8) }
    private func connectors(_ aggregation: String?) throws -> ConnectorDetails {
        let raw = try GooglePlacesMapper.map(response([place("p", aggregation: aggregation)]))
        return StationNormalizer.normalize(raw, from: nil, limit: 20)[0].connectors
    }
    private func group(_ type: String, _ kw: String, _ count: Int) -> String {
        #"{"type":"EV_CONNECTOR_TYPE_\#(type)","maxChargeRateKw":\#(kw),"count":\#(count),"availableCount":1,"outOfServiceCount":1}"#
    }

    // AC-01 / tests 1-3
    func testConnectorTypeMapping() {
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_CCS_COMBO_2"), .ccs2)
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_TYPE_2"), .type2)
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_CHADEMO"), .chademo)
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_TESLA"), .nacs)
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_OTHER"), .other)
        XCTAssertEqual(GooglePlacesMapper.connectorType("EV_CONNECTOR_TYPE_BRAND_NEW"), .unknown)
        XCTAssertEqual(GooglePlacesMapper.connectorType(nil), .unknown)
        XCTAssertEqual(ConnectorDisplay(ChargingConnector(type: .ccs2, maxPowerKW: 60, count: 4)).typeText, "CCS2")
        XCTAssertEqual(ConnectorDisplay(ChargingConnector(type: .type2, maxPowerKW: 22, count: 2)).typeText, "Type 2")
        XCTAssertEqual(ConnectorDisplay(ChargingConnector(type: .unknown, maxPowerKW: 22, count: 2)).typeText, "Connector type unavailable")
    }

    // AC-02 / tests 4-5
    func testPowerFormatting() {
        func text(_ kw: Double?) -> String { ConnectorDisplay(ChargingConnector(type: .ccs2, maxPowerKW: kw, count: 1)).powerText }
        XCTAssertEqual(text(60), "60 kW")
        XCTAssertEqual(text(120), "120 kW")
        XCTAssertEqual(text(7.4), "7.4 kW")
        XCTAssertEqual(text(59.96), "60 kW")
    }

    // AC-06 / test 6
    func testMissingOrInvalidPowerIsNeverInvented() throws {
        for bad in [nil, 0, -5, Double.nan, Double.infinity] as [Double?] {
            XCTAssertEqual(ConnectorDisplay(ChargingConnector(type: .ccs2, maxPowerKW: bad, count: 1)).powerText, "Charging speed unavailable")
        }
        let details = StationNormalizer.connectors([RawConnector(type: .ccs2, maxPowerKW: 0, count: 2)])
        XCTAssertNil(details.connectors[0].maxPowerKW)
    }

    // AC-03 / tests 7-8
    func testCountSingularAndPlural() {
        func text(_ n: Int?) -> String? { ConnectorDisplay(ChargingConnector(type: .ccs2, maxPowerKW: 60, count: n)).countText }
        XCTAssertEqual(text(1), "1 connector")
        XCTAssertEqual(text(4), "4 connectors")
        XCTAssertNil(text(nil))
        XCTAssertNil(text(0))
    }

    // AC-04 / test 9
    func testMultipleConnectorTypesStayIndependent() throws {
        let details = try connectors("[\(group("CCS_COMBO_2", "120", 2)),\(group("TYPE_2", "22", 2))]")
        XCTAssertEqual(details.connectors.map(\.type), [.ccs2, .type2])
        XCTAssertEqual(details.connectors.map(\.maxPowerKW), [120, 22])
    }

    // AC-05 / test 10
    func testSameTypeDifferentPowerIsNotCollapsed() throws {
        let details = try connectors("[\(group("CCS_COMBO_2", "60", 4)),\(group("CCS_COMBO_2", "120", 2))]")
        XCTAssertEqual(details.connectors.map(\.maxPowerKW), [120, 60])
        XCTAssertEqual(details.connectors.map(\.count), [2, 4])
        XCTAssertEqual(Set(details.connectors.map(\.id)).count, 2)
    }

    func testIdenticalGroupsMergeCounts() {
        let raw = [RawConnector(type: .ccs2, maxPowerKW: 60, count: 2), RawConnector(type: .ccs2, maxPowerKW: 60, count: 3)]
        XCTAssertEqual(StationNormalizer.connectors(raw).connectors, [ChargingConnector(type: .ccs2, maxPowerKW: 60, count: 5)])
    }

    // AC-07 / test 11
    func testMissingConnectorInfoKeepsStation() throws {
        let raw = try GooglePlacesMapper.map(response([place("a"), place("b", aggregation: "[\(group("TYPE_2", "22", 1))]")]))
        let stations = StationNormalizer.normalize(raw, from: nil, limit: 20)
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations.first { $0.id == "a" }?.connectors, .unavailable)
        XCTAssertEqual(try connectors("[]"), .unavailable)
    }

    // AC-09 / test 12
    func testMalformedConnectorDataDoesNotBreakDiscovery() throws {
        let bad = place("bad", aggregation: #"{"oops":true}"#)
        let junk = place("junk", aggregation: #"["x", 5, null]"#)
        let wrongTypes = place("wrong", aggregation: #"[{"type":7,"maxChargeRateKw":"fast","count":"many"}]"#)
        let good = place("good", aggregation: "[\(group("CCS_COMBO_2", "60", 4))]")
        let stations = StationNormalizer.normalize(try GooglePlacesMapper.map(response([bad, junk, wrongTypes, good])), from: nil, limit: 20)
        XCTAssertEqual(stations.count, 4)
        XCTAssertEqual(stations.first { $0.id == "bad" }?.connectors, .unavailable)
        XCTAssertEqual(stations.first { $0.id == "junk" }?.connectors, .unavailable)
        let wrong = stations.first { $0.id == "wrong" }?.connectors.connectors
        XCTAssertEqual(wrong, [ChargingConnector(type: .unknown, maxPowerKW: nil, count: nil)])
        XCTAssertEqual(stations.first { $0.id == "good" }?.connectors.connectors.first?.count, 4)
    }

    func testWholeResponseFailureStillThrowsSafeError() {
        XCTAssertThrowsError(try GooglePlacesMapper.map(Data("not json".utf8)))
        XCTAssertEqual(try GooglePlacesMapper.map(Data("{}".utf8)), [])
    }

    func testAvailabilityFieldsAreNeverModelled() throws {
        let station = StationNormalizer.normalize(try GooglePlacesMapper.map(response([place("p", aggregation: "[\(group("TYPE_2", "22", 3))]")])), from: nil, limit: 1)[0]
        XCTAssertEqual(station.connectors.connectors[0].count, 3)   // total count, not availableCount (1)
        XCTAssertFalse(String(describing: station).contains("available:"))
    }

    // test 13
    @MainActor func testSwitchingStationsSwitchesConnectors() async {
        struct Loc: LocationProviding {
            var authorization: LocationAuthorization { .authorized }
            func requestAuthorization() async -> LocationAuthorization { .authorized }
            func currentLocation() async throws -> Coordinate { Coordinate(latitude: 17.4, longitude: 78.3) }
        }
        struct Prov: ChargerProvider {
            func search(near location: Coordinate, config: ChargerDiscoveryConfig) async throws -> [RawStation] {
                [RawStation(id: "A", name: "A", latitude: 17.41, longitude: 78.3, address: nil, source: "t", connectors: [RawConnector(type: .ccs2, maxPowerKW: 60, count: 4)]),
                 RawStation(id: "B", name: "B", latitude: 17.42, longitude: 78.3, address: nil, source: "t", connectors: [RawConnector(type: .type2, maxPowerKW: 22, count: 2)]),
                 RawStation(id: "C", name: "C", latitude: 17.43, longitude: 78.3, address: nil, source: "t", connectors: nil)]
            }
        }
        let vm = ChargerDiscoveryViewModel(location: Loc(), provider: Prov())
        await vm.load()
        vm.select(id: "A")
        XCTAssertEqual(vm.selectedStation?.connectors.connectors.first?.type, .ccs2)
        vm.select(id: "B")
        XCTAssertEqual(vm.selectedStation?.connectors.connectors, [ChargingConnector(type: .type2, maxPowerKW: 22, count: 2)])
        vm.select(id: "C")
        XCTAssertEqual(vm.selectedStation?.connectors, .unavailable)
        XCTAssertEqual(vm.stations.count, 3)   // discovery unaffected
    }

    // Request + provider selection
    func testRequestKeepsKeyInHeaderAndFieldMaskExcludesAvailability() throws {
        let request = try GooglePlacesRequest.make(location: Coordinate(latitude: 17.4, longitude: 78.3), config: .default, apiKey: "SECRET", bundleID: "com.voltiq.ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Key"), "SECRET")
        XCTAssertFalse(request.url!.absoluteString.contains("SECRET"))
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("SECRET"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"), "com.voltiq.ios")
        let mask = request.value(forHTTPHeaderField: "X-Goog-FieldMask") ?? ""
        XCTAssertTrue(mask.contains("places.evChargeOptions"))
        XCTAssertFalse(mask.lowercased().contains("pric"))
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("electric_vehicle_charging_station"))
        XCTAssertTrue(body.contains("5000"))
    }

    func testMissingKeyThrowsSafeError() {
        for key in ["", "  ", "$(GOOGLE_PLACES_API_KEY)"] {
            XCTAssertThrowsError(try GooglePlacesRequest.make(location: Coordinate(latitude: 1, longitude: 1), config: .default, apiKey: key, bundleID: nil)) {
                XCTAssertEqual($0 as? ChargerDiscoveryError, .provider)
            }
        }
    }
}

#if canImport(UIKit) && !SWIFT_PACKAGE
final class ProviderFactoryTests: XCTestCase {
    func testFallsBackToMapKitWithoutKeyAndUsesGoogleWithKey() {
        XCTAssertTrue(ChargerProviderFactory.make(apiKey: nil) is MapKitChargerProvider)
        XCTAssertTrue(ChargerProviderFactory.make(apiKey: "") is MapKitChargerProvider)
        XCTAssertTrue(ChargerProviderFactory.make(apiKey: "$(GOOGLE_PLACES_API_KEY)") is MapKitChargerProvider)
        XCTAssertTrue(ChargerProviderFactory.make(apiKey: "abc") is GooglePlacesChargerProvider)
    }
}
#endif
