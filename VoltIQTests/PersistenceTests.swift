import XCTest
@testable import VoltIQ

final class PersistenceTests: XCTestCase {
    func testPerUserSettingsLogsAndReceiptsSurviveReload() throws {
        let suite = "voltiq-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let repository = DeviceRepository(defaults: defaults, receiptDirectory: directory)
        var first = UserProfile(name: "alice")
        first.preferences.capacity = 60
        first.settings.acEfficiency = 90
        let second = UserProfile(name: "bob")
        let state = DeviceState(selectedUserID: first.id, users: [first, second])
        try repository.save(state)
        let reloaded = try DeviceRepository(defaults: defaults, receiptDirectory: directory).load()
        XCTAssertEqual(reloaded.users, state.users)
        XCTAssertEqual(reloaded.selectedUserID, first.id)
        XCTAssertEqual(reloaded.users[1].preferences.capacity, 79)
        try repository.saveReceipt(Data([1, 2, 3]), userID: first.id, timestamp: 1000)
        XCTAssertEqual(try Data(contentsOf: repository.receiptURL(userID: first.id, timestamp: 1000)), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.receiptURL(userID: second.id, timestamp: 1000).path))
        repository.removeReceipts(userID: first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.receiptURL(userID: first.id, timestamp: 1000).path))
    }

    func testCorruptStateIsReportedAndNotSilentlyReset() throws {
        let suite = "voltiq-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: DeviceRepository.stateKey)
        XCTAssertThrowsError(try DeviceRepository(defaults: defaults).load())
        XCTAssertEqual(defaults.data(forKey: DeviceRepository.stateKey), Data("invalid".utf8))
    }

    func testNamesNormalizeWithoutCreatingDuplicateCaseVariants() {
        XCTAssertEqual(UserProfile.normalize("  Alice   SMITH \n"), "alice smith")
        XCTAssertEqual(UserProfile.normalize(String(repeating: "x", count: 30)).count, 24)
    }
}

#if canImport(UIKit)
@MainActor
final class AppStoreTests: XCTestCase {
    func testSwitchingUsersKeepsPreferencesOperatorsAndLogsSeparate() throws {
        let suite = "voltiq-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let repository = DeviceRepository(defaults: defaults, receiptDirectory: directory)
        let store = AppStore(repository: repository)
        store.addUser("ALICE")
        let alice = try XCTUnwrap(store.profile?.id)
        store.updateProfile { $0.preferences.capacity = 60; $0.preferences.appearance = .dark }
        var op = ChargingOperator()
        op.name = "Local"
        op.rate = 10
        op.gstIncluded = false
        store.saveOperator(op)
        store.selectOperator(op.id)
        XCTAssertEqual(store.profile?.preferences.gstTreatment, .added)
        store.setRate(15)
        XCTAssertNil(store.profile?.preferences.operatorID)
        XCTAssertEqual(store.profile?.preferences.gstTreatment, GSTTreatment.none)
        var draft = ChargeDraft()
        draft.start = 20; draft.end = 80; draft.billed = 40; draft.amount = 600
        for _ in 0..<3 { try store.saveCharge(draft, receipt: Data([1, 2, 3])) }
        XCTAssertEqual(store.learnedPrompt, .dc)
        XCTAssertEqual(Set(store.profile?.entries.map(\.timestamp) ?? []).count, 3)
        let photoEntry = try XCTUnwrap(store.profile?.entries.first)
        let photoURL = try XCTUnwrap(store.receiptURL(photoEntry))
        store.addUser("bob")
        XCTAssertEqual(store.profile?.preferences.capacity, 79)
        XCTAssertTrue(store.profile?.operators.isEmpty == true)
        XCTAssertTrue(store.profile?.entries.isEmpty == true)
        store.chooseUser(alice)
        XCTAssertEqual(store.profile?.preferences.capacity, 60)
        XCTAssertEqual(store.profile?.entries.count, 3)
        XCTAssertEqual(AppStore(repository: repository).profile?.entries.count, 3)
        store.deleteUser(alice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
    }

    func testLogCapPrunesOldReceiptAndClearRemovesPhotos() throws {
        let suite = "voltiq-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let repository = DeviceRepository(defaults: defaults, receiptDirectory: directory)
        let store = AppStore(repository: repository)
        store.addUser("alice")
        var draft = ChargeDraft()
        draft.date = Date(timeIntervalSince1970: 1000)
        draft.start = 20; draft.end = 80; draft.billed = 60; draft.amount = 1000
        try store.saveCharge(draft, receipt: Data([1]))
        let oldURL = try XCTUnwrap(store.receiptURL(try XCTUnwrap(store.profile?.entries.first)))
        store.updateProfile { profile in
            for timestamp in 1000001...1000499 {
                profile.entries.append(ChargeEntry(timestamp: Double(timestamp), energy: 10, cost: 10, rate: 1, gst: .none, chargerPower: nil))
            }
        }
        draft.date = Date(timeIntervalSince1970: 2000)
        try store.saveCharge(draft, receipt: Data([2]))
        XCTAssertEqual(store.profile?.entries.count, 500)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        let newURL = try XCTUnwrap(store.receiptURL(try XCTUnwrap(store.profile?.entries.last)))
        store.clearHistory()
        XCTAssertTrue(store.profile?.entries.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }
}
#endif
