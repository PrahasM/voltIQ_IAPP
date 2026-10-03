import Foundation

struct StationRef: Codable, Equatable {
    var id: String
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double

    init(_ station: ChargingStation) {
        id = station.id; name = station.name; address = station.address
        latitude = station.latitude; longitude = station.longitude
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// A station the driver intends to charge at (or is charging at), kept until it becomes a log entry.
struct PlannedSession: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case planned, inProgress }

    struct EstimateSnapshot: Codable, Equatable {
        var targetPercent: Double
        var hours: Double
        var energyToBuy: Double
        var cost: Double
        var rate: Double
        var rateSource: PriceSource
    }

    var id = UUID()
    var createdAt: Date
    var status = Status.planned
    var startedAt: Date?
    var startPercent: Double?
    var station: StationRef
    var connectorType: ConnectorType?
    var powerKW: Double?
    var estimate: EstimateSnapshot?

    init(plan: ChargePlan, now: Date = Date()) {
        createdAt = now
        station = StationRef(plan.station)
        let connector = plan.selected?.connector
        connectorType = connector?.type
        powerKW = connector?.maxPowerKW
        estimate = plan.estimate.map {
            EstimateSnapshot(targetPercent: $0.targetPercent, hours: $0.hours, energyToBuy: $0.energyToBuy, cost: $0.cost, rate: $0.rate, rateSource: $0.rateSource)
        }
    }

    mutating func start(percent: Double, now: Date = Date()) throws {
        guard percent.isFinite, (0...100).contains(percent) else { throw CalculationError.invalid("Enter a starting charge between 0% and 100%.") }
        status = .inProgress
        startedAt = now
        startPercent = percent
    }

    /// Prefills the log form. Only values the plan really has are filled; the driver confirms the actuals.
    func draft(now: Date = Date()) -> ChargeDraft {
        var draft = ChargeDraft()
        draft.date = startedAt ?? now
        draft.type = connectorType.flatMap(ChargePlanner.chargerType(for:)) ?? .dc
        draft.power = powerKW
        draft.start = startPercent
        draft.station = station
        draft.connectorType = connectorType
        draft.plannedSessionID = id
        if let estimate {
            draft.end = (estimate.targetPercent * 10).rounded() / 10
            draft.billed = ChargeDraft.round(estimate.energyToBuy)
            draft.amount = ChargeDraft.round(estimate.cost)
            draft.rate = estimate.rate
        }
        return draft
    }
}
