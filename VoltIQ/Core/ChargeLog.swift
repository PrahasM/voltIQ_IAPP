import Foundation

struct ChargeDraft {
    var date = Date()
    var operatorID: String?
    var type = ChargerType.dc
    var power: Double?
    var start: Double?
    var end: Double?
    var billed: Double?
    var amount: Double?
    var rate: Double?
    var idle: Double?
    var odometer: Double?

    func entry(capacity: Double, operator op: ChargingOperator?, manualGST: GSTTreatment) throws -> ChargeEntry {
        guard date.timeIntervalSince1970.isFinite, capacity.isFinite, capacity > 0 else { throw CalculationError.invalid("Set your battery capacity on the Calculator first.") }
        guard let start, start.isFinite, (0...100).contains(start), let end, end.isFinite,
              (0...100).contains(end), end > start else { throw CalculationError.invalid("Enter start and end percentages (0–100); end must be higher.") }
        guard let billed, billed.isFinite, billed > 0 else { throw CalculationError.invalid("kWh billed must be greater than 0.") }
        guard let amount, amount.isFinite, amount >= 0 else { throw CalculationError.invalid("Enter the amount paid (zero or greater).") }
        if let power, !power.isFinite || power <= 0 { throw CalculationError.invalid("Charger power must be greater than 0 kW.") }
        for value in [rate, idle, odometer].compactMap({ $0 }) where !value.isFinite || value < 0 {
            throw CalculationError.invalid("Rate, idle minutes and odometer cannot be negative.")
        }
        let fees = (op?.sessionFee ?? 0) + (op?.idleFee ?? 0) * (idle ?? 0)
        let energy = (end - start) * capacity / 100
        let realEfficiency = energy / billed
        let effectiveRate = (amount + fees) / billed
        let actualRate = rate ?? amount / billed
        guard [fees, energy, realEfficiency, effectiveRate, actualRate].allSatisfy(\.isFinite) else {
            throw CalculationError.invalid("These values are too large. Check the charge details.")
        }
        let gst: GSTTreatment = op.map { $0.gstIncluded ? .included : .added } ?? manualGST
        var entry = ChargeEntry(timestamp: (date.timeIntervalSince1970 * 1000).rounded(), energy: Self.round(energy),
                                cost: Self.round(amount), rate: Self.round(actualRate), gst: gst, chargerPower: power)
        entry.billed = Self.round(billed)
        entry.start = start
        entry.end = end
        entry.type = type
        entry.efficiency = (realEfficiency * 10000).rounded() / 10000
        entry.effectiveRate = Self.round(effectiveRate)
        entry.operatorName = op?.name
        entry.operatorID = op?.id
        entry.fees = fees > 0 ? Self.round(fees) : nil
        entry.idleMinutes = (idle ?? 0) > 0 ? idle : nil
        entry.odometer = odometer
        return entry
    }

    static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

enum ChargeCSV {
    static func export(_ entries: [ChargeEntry]) -> String {
        let headers = "date,energy_kwh,cost_inr,rate_inr_per_kwh,gst_included,charger_kw,kwh_billed,start_pct,end_pct,charger_type,operator,odometer_km,real_efficiency_pct,idle_minutes,fees_inr,effective_inr_per_kwh"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = entries.map { e -> String in
            let cells: [String] = [dateFormatter.string(from: e.date), number(e.energy), number(e.cost), number(e.rate),
                e.gst == .added ? "added" : (e.gst == .included ? "yes" : "no"), number(e.chargerPower),
                number(e.billed), number(e.start), number(e.end), e.type?.rawValue ?? "", e.operatorName ?? "",
                number(e.odometer), number(e.efficiency.map { ChargeDraft.round($0 * 100) }), number(e.idleMinutes),
                number(e.fees), number(e.effectiveRate)]
            return cells.map(escape).joined(separator: ",")
        }
        return ([headers] + rows).joined(separator: "\n")
    }

    private static func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
    private static func escape(_ value: String) -> String {
        value.contains(where: { ",\"\n\r".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
    }
}
