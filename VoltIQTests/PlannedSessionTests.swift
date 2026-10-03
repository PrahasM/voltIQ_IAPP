import XCTest
@testable import VoltIQ

final class PlannedSessionTests: XCTestCase {
    private let eff: (ChargerType) -> Double = { $0 == .dc ? 0.92 : 0.87 }
    private func station(_ connectors: [ChargingConnector]?, address: String? = "Hitech City, Hyderabad") -> ChargingStation {
        ChargingStation(id: "p1", name: "ChargeZone, \"Hitech\"", latitude: 17.4, longitude: 78.3, address: address, distanceMeters: 900, source: "t",
                        connectors: connectors.map { .available($0) } ?? .unavailable)
    }
    private func plan(_ s: ChargingStation) -> ChargePlan {
        ChargePlanner.plan(station: s, carConnector: .ccs2, prefs: Preferences(), settings: CarSettings(), efficiency: eff)
    }
    private let full = ChargingConnector(type: .ccs2, maxPowerKW: 60, count: 4, availableCount: 2)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSessionFromFullPlanKeepsStationConnectorAndEstimate() {
        let p = plan(station([full]))
        let session = PlannedSession(plan: p, now: now)
        XCTAssertEqual(session.status, .planned)
        XCTAssertEqual(session.station.id, "p1")
        XCTAssertEqual(session.connectorType, .ccs2)
        XCTAssertEqual(session.powerKW, 60)
        XCTAssertEqual(session.estimate?.targetPercent, 85)
        XCTAssertEqual(session.estimate?.cost, p.estimate?.cost)
        XCTAssertEqual(session.estimate?.energyToBuy, p.estimate?.energyToBuy)
    }

    func testStationWithNoConnectorDataCanStillBePlannedWithoutInventingValues() {
        let session = PlannedSession(plan: plan(station(nil)), now: now)
        XCTAssertNil(session.connectorType)
        XCTAssertNil(session.powerKW)
        XCTAssertNil(session.estimate)
        let draft = session.draft(now: now)
        XCTAssertNil(draft.power); XCTAssertNil(draft.billed); XCTAssertNil(draft.amount); XCTAssertNil(draft.end); XCTAssertNil(draft.rate)
        XCTAssertEqual(draft.station?.name, "ChargeZone, \"Hitech\"")
    }

    func testStartValidatesPercentAndRecordsTime() throws {
        var session = PlannedSession(plan: plan(station([full])), now: now)
        for bad in [Double.nan, -1, 101, .infinity] { XCTAssertThrowsError(try session.start(percent: bad)); XCTAssertEqual(session.status, .planned) }
        try session.start(percent: 30, now: now.addingTimeInterval(60))
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.startPercent, 30)
        XCTAssertEqual(session.startedAt, now.addingTimeInterval(60))
    }

    func testDraftPrefillsFromEstimateAndEntryCarriesStation() throws {
        var session = PlannedSession(plan: plan(station([full])), now: now)
        try session.start(percent: 30, now: now)
        let draft = session.draft(now: now)
        let est = try XCTUnwrap(session.estimate)
        XCTAssertEqual(draft.start, 30)
        XCTAssertEqual(draft.end, 85)
        XCTAssertEqual(draft.billed, ChargeDraft.round(est.energyToBuy))
        XCTAssertEqual(draft.amount, ChargeDraft.round(est.cost))
        XCTAssertEqual(draft.type, .dc)
        XCTAssertEqual(draft.power, 60)
        XCTAssertEqual(draft.plannedSessionID, session.id)
        let entry = try draft.entry(capacity: 79, operator: nil, manualGST: .included)
        XCTAssertEqual(entry.stationID, "p1")
        XCTAssertEqual(entry.stationName, "ChargeZone, \"Hitech\"")
        XCTAssertEqual(entry.stationAddress, "Hitech City, Hyderabad")
        XCTAssertEqual(entry.connectorType, .ccs2)
    }

    func testEntryStationKeysRoundTripAndAreOmittedWhenNil() throws {
        var entry = ChargeEntry(timestamp: 1, energy: 10, cost: 100, rate: 10, gst: .none, chargerPower: 60)
        let plain = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        for key in ["\"si\"", "\"sn\"", "\"sa\"", "\"ct\""] { XCTAssertFalse(plain.contains(key)) }
        entry.stationID = "p1"; entry.stationName = "S"; entry.stationAddress = "A"; entry.connectorType = .type2
        let back = try JSONDecoder().decode(ChargeEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back.stationID, "p1"); XCTAssertEqual(back.stationName, "S"); XCTAssertEqual(back.stationAddress, "A"); XCTAssertEqual(back.connectorType, .type2)
        let junk = Data(#"{"t":1,"e":1,"c":1,"r":1,"g":0,"k":1,"ct":"warp-drive"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ChargeEntry.self, from: junk).connectorType)   // unknown value must not break a log
    }

    func testCSVKeepsFirst16ColumnsAndAppendsStationEscaped() throws {
        var entry = ChargeEntry(timestamp: 1_720_000_000_000, energy: 10, cost: 250, rate: 25, gst: .included, chargerPower: 60)
        entry.stationName = "Charge, \"Zone\""; entry.connectorType = .ccs2
        let csv = ChargeCSV.export([entry])
        let header = csv.split(separator: "\n")[0]
        XCTAssertTrue(header.hasSuffix("effective_inr_per_kwh,station,connector_type"))
        XCTAssertEqual(header.split(separator: ",").count, 18)
        XCTAssertTrue(csv.contains("\"Charge, \"\"Zone\"\"\",ccs2"))
    }

    func testProfileJSONWithoutPlannedSessionDecodesAndWithItRoundTrips() throws {
        var profile = UserProfile(name: "alice")
        let encoded = try JSONEncoder().encode(profile)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "plannedSession")
        XCTAssertNil(try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object)).plannedSession)
        profile.plannedSession = PlannedSession(plan: plan(station([full])), now: now)
        XCTAssertEqual(try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
}

#if canImport(UIKit) && !SWIFT_PACKAGE
@MainActor
final class PlannedSessionStoreTests: XCTestCase {
    private let eff: (ChargerType) -> Double = { _ in 0.9 }
    private func makeStore() throws -> (AppStore, DeviceRepository, UserDefaults, URL, String) {
        let suite = "voltiq-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let repo = DeviceRepository(defaults: defaults, receiptDirectory: dir)
        let store = AppStore(repository: repo)
        store.addUser("alice")
        return (store, repo, defaults, dir, suite)
    }
    private func plan(_ id: String = "p1") -> ChargePlan {
        let s = ChargingStation(id: id, name: "Station \(id)", latitude: 17, longitude: 78, address: nil, distanceMeters: 10, source: "t",
                                connectors: .available([ChargingConnector(type: .ccs2, maxPowerKW: 60, count: 2, availableCount: 1)]))
        return ChargePlanner.plan(station: s, carConnector: nil, prefs: Preferences(), settings: CarSettings(), efficiency: eff)
    }

    func testPlanPersistsAcrossReloadAndPlannedCanBeReplaced() throws {
        let (store, repo, defaults, dir, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        try store.planCharge(plan("a"))
        try store.planCharge(plan("b"))
        XCTAssertEqual(AppStore(repository: repo).profile?.plannedSession?.station.id, "b")
    }

    func testCannotPlanWhileInProgressAndCancelClears() throws {
        let (store, _, defaults, dir, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        try store.planCharge(plan("a"), startPercent: 25)
        XCTAssertEqual(store.profile?.plannedSession?.status, .inProgress)
        XCTAssertThrowsError(try store.planCharge(plan("b")))
        XCTAssertEqual(store.profile?.plannedSession?.station.id, "a")
        XCTAssertThrowsError(try store.planCharge(plan("c"), startPercent: 500))
        store.cancelPlan()
        XCTAssertNil(store.profile?.plannedSession)
    }

    func testSavingTheMatchingChargeClearsPlanAndKeepsStationOnEntry() throws {
        let (store, _, defaults, dir, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        try store.planCharge(plan("a"), startPercent: 25)
        var draft = try XCTUnwrap(store.profile?.plannedSession).draft()
        draft.start = 25; draft.end = 80; draft.billed = 40; draft.amount = 900
        try store.saveCharge(draft, receipt: nil)
        XCTAssertNil(store.profile?.plannedSession)
        XCTAssertEqual(store.profile?.entries.last?.stationName, "Station a")
    }

    func testInvalidSaveLeavesThePlanAndUnrelatedSaveDoesNotClearIt() throws {
        let (store, _, defaults, dir, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        try store.planCharge(plan("a"), startPercent: 25)
        var bad = try XCTUnwrap(store.profile?.plannedSession).draft()
        bad.end = nil
        XCTAssertThrowsError(try store.saveCharge(bad, receipt: nil))
        XCTAssertNotNil(store.profile?.plannedSession)
        var other = ChargeDraft(); other.start = 10; other.end = 50; other.billed = 30; other.amount = 500
        try store.saveCharge(other, receipt: nil)
        XCTAssertNotNil(store.profile?.plannedSession)
    }

    func testDeletingDriverRemovesTheirPlan() throws {
        let (store, _, defaults, dir, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        try store.planCharge(plan("a"))
        let id = try XCTUnwrap(store.profile?.id)
        store.deleteUser(id)
        XCTAssertNil(store.state.users.first { $0.id == id })
    }
}
#endif
