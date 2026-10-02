import Foundation

final class DeviceRepository {
    static let stateKey = "voltiq-state-v1"
    let defaults: UserDefaults
    let receiptDirectory: URL

    init(defaults: UserDefaults = .standard, receiptDirectory: URL? = nil) {
        self.defaults = defaults
        self.receiptDirectory = receiptDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoltIQ/Receipts", isDirectory: true)
    }

    func load() throws -> DeviceState {
        guard let data = defaults.data(forKey: Self.stateKey) else { return DeviceState() }
        let state = try JSONDecoder().decode(DeviceState.self, from: data)
        guard state.version == 1 else { throw CalculationError.invalid("This device's data needs a newer version of voltIQ.") }
        return state
    }

    func save(_ state: DeviceState) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: Self.stateKey)
    }

    func receiptURL(userID: UUID, timestamp: Double) -> URL {
        receiptDirectory.appendingPathComponent(userID.uuidString, isDirectory: true)
            .appendingPathComponent(String(format: "%.0f.jpg", timestamp))
    }

    func saveReceipt(_ data: Data, userID: UUID, timestamp: Double) throws {
        let url = receiptURL(userID: userID, timestamp: timestamp)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func removeReceipt(userID: UUID, timestamp: Double) {
        try? FileManager.default.removeItem(at: receiptURL(userID: userID, timestamp: timestamp))
    }

    func removeReceipts(userID: UUID) {
        try? FileManager.default.removeItem(at: receiptDirectory.appendingPathComponent(userID.uuidString, isDirectory: true))
    }
}
