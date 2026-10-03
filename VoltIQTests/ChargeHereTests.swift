import XCTest
@testable import VoltIQ

final class ChargeHereTests: XCTestCase {
    private let eff: (ChargerType) -> Double = { $0 == .dc ? 0.92 : 0.87 }
    private func conn(_ type: ConnectorType, _ kw: Double?, _ count: Int? = 2, avail: Int? = nil) -> ChargingConnector {
        ChargingConnector(type: type, maxPowerKW: kw, count: count, availableCount: avail)
    }
    private func station(_ list: [ChargingConnector]?, price: Double? = nil, url: URL? = nil) -> ChargingStation {
        ChargingStation(id: "s", name: "S", latitude: 17.4, longitude: 78.3, address: nil, distanceMeters: 1200, source: "t",
                        connectors: list.map { .available($0) } ?? .unavailable, pricePerKWh: price, providerURL: url)
    }
    private func plan(_ s: ChargingStation, car: ConnectorType? = nil, chosen: String? = nil, prefs: Preferences = Preferences()) -> ChargePlan {
        ChargePlanner.plan(station: s, carConnector: car, prefs: prefs, settings: CarSettings(), efficiency: eff, chosenID: chosen)
    }

    // Ranking
    func testStationsAreAscendingByDistanceWithNilLastAndStableTies() {
        func raw(_ id: String, _ lat: Double) -> RawStation { RawStation(id: id, name: id, latitude: lat, longitude: 78, address: nil, source: "t") }
        let list = StationNormalizer.normalize([raw("c", 17.03), raw("b", 17.01), raw("a", 17.01), raw("d", 17.02)], from: Coordinate(latitude: 17, longitude: 78), limit: 10)
        XCTAssertEqual(list.map(\.id), ["a", "b", "d", "c"])
        let none = StationNormalizer.normalize([raw("x", 17.0), raw("y", 17.5)], from: nil, limit: 10)
        XCTAssertEqual(none.map(\.id), ["x", "y"])
    }

    // Formatting labels
    func testFormattingLabelsPresentAndAbsent() {
        XCTAssertEqual(StationFormatting.availability(conn(.ccs2, 60, 4, avail: 2)), "2 of 4 available")
        XCTAssertEqual(StationFormatting.availability(conn(.ccs2, 60, nil, avail: 2)), "2 available")
        XCTAssertEqual(StationFormatting.availability(conn(.ccs2, 60, 4)), "Availability unavailable")
        XCTAssertEqual(StationFormatting.price(18), "₹18/kWh")
        XCTAssertEqual(StationFormatting.price(18.5), "₹18.50/kWh")
        for bad in [nil, 0, -1, Double.nan] as [Double?] { XCTAssertEqual(StationFormatting.price(bad), "Price unavailable") }
        XCTAssertEqual(StationFormatting.provider(nil), "Provider unavailable")
        XCTAssertEqual(StationFormatting.provider("  "), "Provider unavailable")
        XCTAssertEqual(StationFormatting.provider("ChargeZone"), "ChargeZone")
        let s = station([conn(.ccs2, 60, 4, avail: 1), conn(.type2, 22, 2, avail: 2)])
        XCTAssertEqual(StationFormatting.stationAvailability(s), "3 of 6 available")
        XCTAssertEqual(StationFormatting.connectorSummary(s), "CCS2 · 60 kW, Type 2 · 22 kW")
        XCTAssertEqual(StationFormatting.stationAvailability(station([conn(.ccs2, 60)])), "Availability unavailable")
        XCTAssertEqual(StationFormatting.connectorSummary(station(nil)), "Connector details unavailable")
    }

    func testUpdatedTextUsesInjectedNowAndOmitsWhenUnknown() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(StationFormatting.updated(now.addingTimeInterval(-300), now: now), "Updated 5 min ago")
        XCTAssertEqual(StationFormatting.updated(now.addingTimeInterval(-10), now: now), "Updated just now")
        XCTAssertEqual(StationFormatting.updated(now.addingTimeInterval(-7200), now: now), "Updated 2 hr ago")
        XCTAssertNil(StationFormatting.updated(nil, now: now))
    }

    // Provider availability
    func testPlacesAvailabilityAndTimestampAreParsed() throws {
        let json = #"{"places":[{"id":"p","displayName":{"text":"P"},"location":{"latitude":17.4,"longitude":78.3},"evChargeOptions":{"connectorAggregation":[{"type":"EV_CONNECTOR_TYPE_CCS_COMBO_2","maxChargeRateKw":60,"count":4,"availableCount":2,"outOfServiceCount":1,"availabilityLastUpdateTime":"2026-10-03T10:00:00Z"}]}}]}"#
        let c = StationNormalizer.normalize(try GooglePlacesMapper.map(Data(json.utf8)), from: nil, limit: 1)[0].connectors.connectors[0]
        XCTAssertEqual(c.availableCount, 2)
        XCTAssertEqual(c.outOfServiceCount, 1)
        XCTAssertEqual(c.availabilityUpdated, ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z"))
    }

    func testImplausibleAvailabilityBecomesUnknownAndMergeSums() {
        let over = StationNormalizer.connectors([RawConnector(type: .ccs2, maxPowerKW: 60, count: 2, availableCount: 5)])
        XCTAssertNil(over.connectors[0].availableCount)
        let neg = StationNormalizer.connectors([RawConnector(type: .ccs2, maxPowerKW: 60, count: 2, availableCount: -1)])
        XCTAssertNil(neg.connectors[0].availableCount)
        let merged = StationNormalizer.connectors([RawConnector(type: .ccs2, maxPowerKW: 60, count: 2, availableCount: 1), RawConnector(type: .ccs2, maxPowerKW: 60, count: 2, availableCount: 2)])
        XCTAssertEqual(merged.connectors[0].count, 4)
        XCTAssertEqual(merged.connectors[0].availableCount, 3)
    }

    // Preselection
    func testPreselectsFastestAvailableCompatible() {
        let s = station([conn(.ccs2, 120, 2, avail: 0), conn(.ccs2, 60, 2, avail: 1), conn(.chademo, 90, 2, avail: 2), conn(.type2, 22, 2, avail: 2)])
        XCTAssertEqual(plan(s, car: .ccs2).selected?.connector.maxPowerKW, 60)
        XCTAssertEqual(plan(s, car: nil).selected?.connector.maxPowerKW, 90)   // no car set: fastest available
        XCTAssertEqual(plan(s, car: .type2).selected?.connector.type, .type2)
    }

    func testUserCanChangeTheSelection() {
        let s = station([conn(.ccs2, 60, 2, avail: 1), conn(.type2, 22, 2, avail: 2)])
        let p = plan(s, car: .ccs2)
        let other = p.connectors.first { $0.connector.type == .type2 }!.id
        XCTAssertEqual(plan(s, car: .ccs2, chosen: other).selected?.connector.type, .type2)
        XCTAssertEqual(plan(s, car: .ccs2, chosen: "nonsense").selectedID, p.selectedID)
    }

    func testNothingPreselectedWhenNoCompatibleAvailableConnector() {
        let none = plan(station([conn(.ccs2, 60, 2, avail: 0)]), car: .ccs2)
        XCTAssertNil(none.selectedID)
        XCTAssertNil(none.estimate)
        XCTAssertTrue(none.estimateNote?.contains("No available compatible connector") == true)
        let wrongType = plan(station([conn(.chademo, 50, 2, avail: 2)]), car: .ccs2)
        XCTAssertNil(wrongType.selectedID)
        XCTAssertEqual(wrongType.connectors[0].compatibility, .incompatible)
    }

    func testUnknownAvailabilityStillPreselectsFastestCompatibleButIsLabelled() {
        let p = plan(station([conn(.ccs2, 60), conn(.ccs2, 120)]), car: .ccs2)
        XCTAssertEqual(p.selected?.connector.maxPowerKW, 120)
        XCTAssertEqual(p.selected?.availability, .unknown)
        let mixed = plan(station([conn(.ccs2, 120, 2, avail: 0), conn(.ccs2, 60)]), car: .ccs2)
        XCTAssertNil(mixed.selectedID)   // one known-empty, one unknown: don't guess
    }

    func testCompatibilityUnknownWithoutCarOrWithUnknownType() {
        XCTAssertEqual(ChargePlanner.compatibility(.ccs2, car: nil), .unknown)
        XCTAssertEqual(ChargePlanner.compatibility(.unknown, car: .ccs2), .unknown)
        XCTAssertEqual(ChargePlanner.compatibility(.ccs2, car: .ccs2), .compatible)
        XCTAssertEqual(ChargePlanner.compatibility(.type2, car: .ccs2), .incompatible)
    }

    // Estimate
    func testEstimateUsesConnectorPowerAndSavedTargetWithoutMutatingPrefs() throws {
        var prefs = Preferences()
        prefs.mode = .amount
        let before = prefs
        let p = plan(station([conn(.ccs2, 60, 2, avail: 1)]), car: .ccs2, prefs: prefs)
        var expected = before
        expected.mode = .target; expected.chargerID = "station"; expected.customPower = 60; expected.customType = .dc
        let result = try ChargingCalculator.calculate(expected, settings: CarSettings(), efficiency: 0.92)
        XCTAssertEqual(p.estimate?.hours ?? 0, result.hours, accuracy: 1e-9)
        XCTAssertEqual(p.estimate?.cost ?? 0, result.total, accuracy: 1e-9)
        XCTAssertEqual(p.estimate?.targetPercent, 85)
        XCTAssertEqual(prefs, before)
    }

    func testPriceSourceIsLabelled() {
        let saved = plan(station([conn(.ccs2, 60, 2, avail: 1)])).estimate
        XCTAssertEqual(saved?.rateSource, .savedRate)
        XCTAssertEqual(saved?.rate, Preferences().rate)
        let own = plan(station([conn(.ccs2, 60, 2, avail: 1)], price: 18)).estimate
        XCTAssertEqual(own?.rateSource, .station)
        XCTAssertEqual(own?.rate, 18)
        XCTAssertNotEqual(saved?.cost, own?.cost)
    }

    func testEstimateUnavailableWithoutGuessing() {
        let noPower = plan(station([conn(.ccs2, nil, 2, avail: 1)]))
        XCTAssertNil(noPower.estimate)
        XCTAssertTrue(noPower.estimateNote?.contains("charging speed unavailable") == true)
        let nacs = plan(station([conn(.nacs, 150, 2, avail: 1)]))
        XCTAssertNil(nacs.estimate)
        XCTAssertNotNil(nacs.estimateNote)
        let noConnectors = plan(station(nil))
        XCTAssertNil(noConnectors.selectedID)
        XCTAssertEqual(noConnectors.estimateNote, "Connector details unavailable, so no estimate.")
    }

    func testACConnectorUsesACPath() {
        XCTAssertEqual(ChargePlanner.chargerType(for: .type2), .ac)
        XCTAssertEqual(ChargePlanner.chargerType(for: .ccs2), .dc)
        XCTAssertNil(ChargePlanner.chargerType(for: .other))
        XCTAssertNotNil(plan(station([conn(.type2, 22, 2, avail: 1)])).estimate)
    }

    // Handoff (no session is ever started)
    func testHandoffIsProviderAppWhenKnownElseDirections() {
        let url = URL(string: "https://example.com/app")!
        XCTAssertEqual(plan(station([conn(.ccs2, 60)], url: url)).handoff, .providerApp(url))
        XCTAssertEqual(plan(station([conn(.ccs2, 60)])).handoff, .directions(Coordinate(latitude: 17.4, longitude: 78.3)))
    }

    // Persistence compatibility
    func testOldCarSettingsJSONStillDecodesAndNewValueRoundTrips() throws {
        let old = Data(#"{"dcEfficiency":90,"acEfficiency":85,"maxACPower":11,"maxDCPower":150,"taperPercent":40}"#.utf8)
        let decoded = try JSONDecoder().decode(CarSettings.self, from: old)
        XCTAssertNil(decoded.connectorType)
        var settings = CarSettings(); settings.connectorType = .ccs2
        XCTAssertEqual(try JSONDecoder().decode(CarSettings.self, from: JSONEncoder().encode(settings)).connectorType, .ccs2)
    }
}
