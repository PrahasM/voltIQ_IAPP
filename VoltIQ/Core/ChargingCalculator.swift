import Foundation

struct ChargingPhase: Equatable {
    let from: Double
    let to: Double
    let power: Double
    let energyToBuy: Double
    let hours: Double
    let tapered: Bool
}

struct CalculationResult: Equatable {
    let energy: Double
    let energyToBuy: Double
    let finalPercent: Double
    let hours: Double
    let total: Double
    let base: Double
    let gst: Double
    let effectivePower: Double
    let capped: Bool
    let phases: [ChargingPhase]
    var enterKWh: Double { ceil((energyToBuy * 1000).rounded() / 1000) }
}

enum CalculationError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum ChargingCalculator {
    static func calculate(_ prefs: Preferences, settings: CarSettings, efficiency: Double) throws -> CalculationResult {
        guard prefs.capacity.isFinite, prefs.capacity > 0 else { throw CalculationError.invalid("Enter a battery capacity greater than 0 kWh.") }
        guard prefs.current.isFinite, (0...100).contains(prefs.current) else { throw CalculationError.invalid("Current charge must be between 0% and 100%.") }
        guard prefs.chargerPower.isFinite, prefs.chargerPower > 0 else { throw CalculationError.invalid("Enter a charger power greater than 0 kW.") }
        guard prefs.rate.isFinite, prefs.rate > 0 else { throw CalculationError.invalid("Enter a charging rate greater than zero.") }
        guard efficiency.isFinite, (0.5...1).contains(efficiency) else { throw CalculationError.invalid("Charging efficiency must be 50%–100%.") }
        let carLimit = prefs.chargerType == .ac ? settings.maxACPower : settings.maxDCPower
        guard carLimit.isFinite, (1...1000).contains(carLimit), settings.taperPercent.isFinite,
              (10...100).contains(settings.taperPercent) else { throw CalculationError.invalid("Check your car power limits and taper setting.") }
        switch prefs.mode {
        case .target:
            guard prefs.target.isFinite, (0...100).contains(prefs.target), prefs.target > prefs.current else {
                throw CalculationError.invalid("Target charge must be higher than current charge, up to 100%.")
            }
        case .amount:
            guard prefs.budget.isFinite, prefs.budget > 0 else { throw CalculationError.invalid("Enter an amount greater than ₹0.") }
        case .time:
            guard prefs.minutes.isFinite, prefs.minutes > 0 else { throw CalculationError.invalid("Enter a charging time greater than 0 minutes.") }
        }
        if prefs.mode != .target && prefs.current >= 100 { throw CalculationError.invalid("Your battery is already full.") }
        let power = min(prefs.chargerPower, carLimit)
        let taper = settings.taperPercent / 100
        let grossRate = prefs.rate * (prefs.gstTreatment == .added ? 1.18 : 1)
        let rawEnergy: Double
        switch prefs.mode {
        case .target: rawEnergy = prefs.capacity * (prefs.target - prefs.current) / 100
        case .amount: rawEnergy = prefs.budget / grossRate * efficiency
        case .time:
            rawEnergy = energyForHours(current: prefs.current, capacity: prefs.capacity, power: power,
                                       type: prefs.chargerType, efficiency: efficiency, taper: taper, hours: prefs.minutes / 60)
        }
        let room = prefs.capacity * (100 - prefs.current) / 100
        let capped = prefs.mode != .target && rawEnergy > room
        let energy = min(rawEnergy, room)
        let energyToBuy = energy / efficiency
        let final = prefs.mode == .target ? prefs.target : min(100, prefs.current + energy / prefs.capacity * 100)
        let phases = phases(current: prefs.current, target: final, capacity: prefs.capacity, power: power,
                            type: prefs.chargerType, efficiency: efficiency, taper: taper)
        let hours = prefs.mode == .time && !capped ? prefs.minutes / 60 : phases.reduce(0) { $0 + $1.hours }
        let total = prefs.mode == .amount && !capped ? prefs.budget : energyToBuy * grossRate
        let base = prefs.gstTreatment == .none ? total : total / 1.18
        guard [energy, energyToBuy, final, hours, total, base].allSatisfy(\.isFinite) else {
            throw CalculationError.invalid("These inputs are too large. Enter smaller values.")
        }
        return .init(energy: energy, energyToBuy: energyToBuy, finalPercent: final, hours: hours, total: total,
                     base: base, gst: total - base, effectivePower: power, capped: capped, phases: phases)
    }

    static func phases(current: Double, target: Double, capacity: Double, power: Double,
                       type: ChargerType, efficiency: Double, taper: Double) -> [ChargingPhase] {
        let split = type == .dc ? min(max(current, 80), target) : target
        var result: [ChargingPhase] = []
        for (from, to, phasePower, tapered) in [(current, split, power, false), (split, target, power * taper, true)] where to > from {
            let buy = capacity * (to - from) / 100 / efficiency
            result.append(.init(from: from, to: to, power: phasePower, energyToBuy: buy, hours: buy / phasePower, tapered: tapered))
        }
        return result
    }

    static func energyForHours(current: Double, capacity: Double, power: Double, type: ChargerType,
                               efficiency: Double, taper: Double, hours: Double) -> Double {
        if type == .ac { return power * hours * efficiency }
        if current >= 80 { return power * taper * hours * efficiency }
        let to80 = capacity * (80 - current) / 100
        let hoursTo80 = to80 / efficiency / power
        if hours <= hoursTo80 { return power * hours * efficiency }
        return to80 + power * taper * (hours - hoursTo80) * efficiency
    }
}
