import Foundation

enum Compatibility: Equatable { case compatible, incompatible, unknown }
enum Availability: Equatable { case available(Int), none, unknown }

enum ChargeHandoff: Equatable {
    case providerApp(URL)
    case directions(Coordinate)
}

struct PlannedConnector: Identifiable, Equatable {
    let connector: ChargingConnector
    let compatibility: Compatibility
    let availability: Availability
    var id: String { connector.id }
}

enum PriceSource: Equatable { case station, savedRate }

struct ChargeEstimate: Equatable {
    let hours: Double
    let cost: Double
    let rate: Double
    let rateSource: PriceSource
    let targetPercent: Double
}

struct ChargePlan: Equatable {
    let station: ChargingStation
    let connectors: [PlannedConnector]
    let selectedID: String?
    /// nil when no connector is selected or the estimate cannot be made without guessing.
    let estimate: ChargeEstimate?
    let estimateNote: String?
    let handoff: ChargeHandoff
    var selected: PlannedConnector? { connectors.first { $0.id == selectedID } }
}

/// Pure planning for "Charge Here". It never starts a session; it only prepares details and a handoff.
enum ChargePlanner {
    static func plan(station: ChargingStation, carConnector: ConnectorType?, prefs: Preferences, settings: CarSettings,
                     efficiency: (ChargerType) -> Double, chosenID: String? = nil) -> ChargePlan {
        let planned = station.connectors.connectors.map { c in
            PlannedConnector(connector: c, compatibility: compatibility(c.type, car: carConnector), availability: availability(c))
        }
        let selectedID = chosenID.flatMap { id in planned.contains { $0.id == id } ? id : nil } ?? preselect(planned)
        let selected = planned.first { $0.id == selectedID }
        let (estimate, note) = estimate(station: station, connector: selected?.connector, prefs: prefs, settings: settings, efficiency: efficiency, hasChoices: !planned.isEmpty)
        let handoff: ChargeHandoff = station.providerURL.map(ChargeHandoff.providerApp) ?? .directions(station.coordinate)
        return ChargePlan(station: station, connectors: planned, selectedID: selectedID, estimate: estimate, estimateNote: note, handoff: handoff)
    }

    static func compatibility(_ type: ConnectorType, car: ConnectorType?) -> Compatibility {
        guard let car else { return .unknown }
        guard type != .unknown else { return .unknown }
        return type == car ? .compatible : .incompatible
    }

    static func availability(_ c: ChargingConnector) -> Availability {
        guard let n = c.availableCount else { return .unknown }
        return n > 0 ? .available(n) : .none
    }

    /// Fastest compatible-or-unknown connector that is available; if availability is unknown everywhere, the fastest candidate.
    static func preselect(_ planned: [PlannedConnector]) -> String? {
        let candidates = planned.filter { $0.compatibility != .incompatible }
        func fastest(_ list: [PlannedConnector]) -> String? { list.max { ($0.connector.maxPowerKW ?? -1) < ($1.connector.maxPowerKW ?? -1) }?.id }
        let available = candidates.filter { if case .available = $0.availability { return true } else { return false } }
        if let id = fastest(available) { return id }
        let unknown = candidates.filter { $0.availability == .unknown }
        return unknown.count == candidates.count ? fastest(unknown) : nil
    }

    /// Standard mapping used only for the estimate; other types are not guessed.
    static func chargerType(for type: ConnectorType) -> ChargerType? {
        switch type {
        case .type2: return .ac
        case .ccs1, .ccs2, .chademo: return .dc
        case .nacs, .other, .unknown: return nil
        }
    }

    private static func estimate(station: ChargingStation, connector: ChargingConnector?, prefs: Preferences, settings: CarSettings,
                                 efficiency: (ChargerType) -> Double, hasChoices: Bool) -> (ChargeEstimate?, String?) {
        guard let connector else {
            return (nil, hasChoices ? "No available compatible connector. Choose another connector or station." : "Connector details unavailable, so no estimate.")
        }
        guard let power = connector.maxPowerKW, power > 0 else { return (nil, "Estimate unavailable: charging speed unavailable.") }
        guard let type = chargerType(for: connector.type) else { return (nil, "Estimate unavailable: connector type isn't supported for estimates.") }
        var copy = prefs
        copy.mode = .target
        copy.chargerID = "station"
        copy.customPower = power
        copy.customType = type
        let source: PriceSource
        if let price = station.pricePerKWh, price.isFinite, price > 0 { copy.rate = price; source = .station } else { source = .savedRate }
        do {
            let result = try ChargingCalculator.calculate(copy, settings: settings, efficiency: efficiency(type))
            return (ChargeEstimate(hours: result.hours, cost: result.total, rate: copy.rate, rateSource: source, targetPercent: result.finalPercent), nil)
        } catch {
            return (nil, "Estimate unavailable: \(error.localizedDescription)")
        }
    }
}
