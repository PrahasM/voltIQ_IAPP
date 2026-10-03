import Combine
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state = DeviceState()
    @Published var storageError: String?
    @Published var learnedPrompt: ChargerType?
    private let repository: DeviceRepository
    private var canSave = true

    init(repository: DeviceRepository = DeviceRepository()) {
        self.repository = repository
        do { state = try repository.load() }
        catch {
            storageError = "Couldn't read the saved data: \(error.localizedDescription)"
            canSave = false
        }
    }

    var profile: UserProfile? { state.users.first { $0.id == state.selectedUserID } }
    var selectedOperator: ChargingOperator? { profile?.operators.first { $0.id == profile?.preferences.operatorID } }
    var result: Result<CalculationResult, Error> {
        guard let profile else { return .failure(CalculationError.invalid("Choose who's charging.")) }
        return Result { try ChargingCalculator.calculate(profile.preferences, settings: profile.settings, efficiency: profile.efficiency(for: profile.preferences.chargerType)) }
    }

    func preference<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { self.profile?.preferences[keyPath: keyPath] ?? fallback }, set: { value in
            self.updateProfile { $0.preferences[keyPath: keyPath] = value }
        })
    }

    func setting(_ keyPath: WritableKeyPath<CarSettings, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: { self.profile?.settings[keyPath: keyPath] ?? fallback }, set: { value in
            self.updateProfile { $0.settings[keyPath: keyPath] = value }
        })
    }

    func carConnector() -> Binding<ConnectorType?> {
        Binding(get: { self.profile?.settings.connectorType }, set: { value in
            self.updateProfile { $0.settings.connectorType = value }
        })
    }

    func updateProfile(_ edit: (inout UserProfile) -> Void) {
        guard let index = state.users.firstIndex(where: { $0.id == state.selectedUserID }) else { return }
        var next = state
        edit(&next.users[index])
        commit(next)
    }

    /// Saves a planned session for the selected driver, optionally already started. Replaces a `planned` one.
    func planCharge(_ plan: ChargePlan, startPercent: Double? = nil, now: Date = Date()) throws {
        guard let index = state.users.firstIndex(where: { $0.id == state.selectedUserID }) else { return }
        if state.users[index].plannedSession?.status == .inProgress {
            throw CalculationError.invalid("A charge is already in progress. Complete or cancel it from History first.")
        }
        var session = PlannedSession(plan: plan, now: now)
        if let startPercent { try session.start(percent: startPercent, now: now) }
        var next = state
        next.users[index].plannedSession = session
        try persist(next)
    }

    func startSession(percent: Double, now: Date = Date()) throws {
        guard let index = state.users.firstIndex(where: { $0.id == state.selectedUserID }),
              var session = state.users[index].plannedSession else { return }
        try session.start(percent: percent, now: now)
        var next = state
        next.users[index].plannedSession = session
        try persist(next)
    }

    func cancelPlan() {
        updateProfile { $0.plannedSession = nil }
    }

    func chooseUser(_ id: UUID) {
        var next = state
        next.selectedUserID = id
        commit(next)
        learnedPrompt = nil
    }

    func addUser(_ rawName: String) {
        let name = UserProfile.normalize(rawName)
        guard !name.isEmpty else { return }
        if let existing = state.users.first(where: { $0.name == name }) { chooseUser(existing.id); return }
        let profile = UserProfile(name: name)
        var next = state
        next.users.append(profile)
        next.selectedUserID = profile.id
        commit(next)
    }

    func deleteUser(_ id: UUID) {
        var next = state
        next.users.removeAll { $0.id == id }
        if next.selectedUserID == id { next.selectedUserID = nil }
        if commit(next) { repository.removeReceipts(userID: id) }
    }

    func selectOperator(_ id: String?) {
        updateProfile { profile in
            profile.preferences.operatorID = id
            if let op = profile.operators.first(where: { $0.id == id }) {
                profile.preferences.rate = op.rate
                profile.preferences.gstIncluded = op.gstIncluded
            }
        }
    }

    func setRate(_ value: Double) {
        updateProfile { profile in
            profile.preferences.rate = value
            if let op = profile.operators.first(where: { $0.id == profile.preferences.operatorID }), abs(op.rate - value) > 0.001 {
                profile.preferences.operatorID = nil
            }
        }
    }

    func saveOperator(_ op: ChargingOperator) {
        updateProfile { profile in
            if let i = profile.operators.firstIndex(where: { $0.id == op.id }) { profile.operators[i] = op }
            else { profile.operators.append(op) }
            if profile.preferences.operatorID == op.id {
                profile.preferences.rate = op.rate
                profile.preferences.gstIncluded = op.gstIncluded
            }
        }
    }

    func deleteOperator(_ id: String) {
        updateProfile { profile in
            profile.operators.removeAll { $0.id == id }
            if profile.preferences.operatorID == id { profile.preferences.operatorID = nil }
        }
    }

    func saveCharge(_ draft: ChargeDraft, receipt: Data?) throws {
        guard let index = state.users.firstIndex(where: { $0.id == state.selectedUserID }) else { return }
        let profile = state.users[index]
        let op = profile.operators.first { $0.id == draft.operatorID }
        var entry = try draft.entry(capacity: profile.preferences.capacity, operator: op, manualGST: profile.preferences.gstIncluded ? .included : .none)
        while profile.entries.contains(where: { $0.timestamp == entry.timestamp }) { entry.timestamp += 1 }
        let learnedBefore = LearnedEfficiency.compute(profile.entries, type: draft.type)
        if let receipt {
            try repository.saveReceipt(receipt, userID: profile.id, timestamp: entry.timestamp)
            entry.photo = 1
        }
        var next = state
        if let planned = draft.plannedSessionID, next.users[index].plannedSession?.id == planned { next.users[index].plannedSession = nil }
        next.users[index].entries.append(entry)
        next.users[index].entries.sort { $0.timestamp < $1.timestamp }
        let removed = Array(next.users[index].entries.dropLast(500))
        next.users[index].entries = Array(next.users[index].entries.suffix(500))
        do { try persist(next) }
        catch {
            repository.removeReceipt(userID: profile.id, timestamp: entry.timestamp)
            throw error
        }
        for old in removed { repository.removeReceipt(userID: profile.id, timestamp: old.timestamp) }
        if learnedBefore == nil, LearnedEfficiency.compute(next.users[index].entries, type: draft.type) != nil,
           !(draft.type == .ac ? profile.preferences.learnAC : profile.preferences.learnDC) { learnedPrompt = draft.type }
    }

    func deleteEntry(_ timestamp: Double) {
        guard let id = profile?.id, let index = state.users.firstIndex(where: { $0.id == id }) else { return }
        var next = state
        next.users[index].entries.removeAll { $0.timestamp == timestamp }
        if commit(next) { repository.removeReceipt(userID: id, timestamp: timestamp) }
    }

    func clearHistory() {
        guard let id = profile?.id, let index = state.users.firstIndex(where: { $0.id == id }) else { return }
        var next = state
        next.users[index].entries = []
        if commit(next) { repository.removeReceipts(userID: id) }
    }

    func receiptURL(_ entry: ChargeEntry) -> URL? {
        guard let id = profile?.id, entry.photo == 1 else { return nil }
        return repository.receiptURL(userID: id, timestamp: entry.timestamp)
    }

    func useLearned(_ type: ChargerType) {
        updateProfile { if type == .ac { $0.preferences.learnAC = true } else { $0.preferences.learnDC = true } }
        learnedPrompt = nil
    }

    private func persist(_ next: DeviceState) throws {
        guard canSave else { throw CalculationError.invalid("Saved data could not be loaded. Reopen the app after restoring your device data.") }
        try repository.save(next)
        state = next
    }

    @discardableResult private func commit(_ next: DeviceState) -> Bool {
        do { try persist(next); return true }
        catch { storageError = "Couldn't save: \(error.localizedDescription)"; return false }
    }
}
