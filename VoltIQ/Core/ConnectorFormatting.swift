import Foundation

/// User-facing strings for a connector group. Never produces nil/null/NaN/"0 kW".
struct ConnectorDisplay: Equatable {
    let typeText: String
    let powerText: String
    let countText: String?

    init(_ connector: ChargingConnector) {
        switch connector.type {
        case .ccs1: typeText = "CCS1"
        case .ccs2: typeText = "CCS2"
        case .type2: typeText = "Type 2"
        case .chademo: typeText = "CHAdeMO"
        case .nacs: typeText = "NACS"
        case .other: typeText = "Other"
        case .unknown: typeText = "Connector type unavailable"
        }
        if let kw = connector.maxPowerKW, kw.isFinite, kw > 0 {
            let rounded = (kw * 10).rounded() / 10
            let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
            powerText = "\(text) kW"
        } else {
            powerText = "Charging speed unavailable"
        }
        if let count = connector.count, count >= 1 { countText = count == 1 ? "1 connector" : "\(count) connectors" }
        else { countText = nil }
    }
}

enum StationFormatting {
    static func availability(_ c: ChargingConnector) -> String {
        guard let available = c.availableCount else { return "Availability unavailable" }
        if let total = c.count { return "\(available) of \(total) available" }
        return "\(available) available"
    }

    static func updated(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "Updated \(Int(seconds / 3600)) hr ago" }
        return "Updated \(Int(seconds / 86_400)) d ago"
    }

    static func price(_ perKWh: Double?) -> String {
        guard let value = perKWh, value.isFinite, value > 0 else { return "Price unavailable" }
        let rounded = (value * 100).rounded() / 100
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return "₹\(text)/kWh"
    }

    static func provider(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Provider unavailable" : trimmed
    }

    /// Station-level availability, e.g. "3 of 6 available"; unknown when no group reports it.
    static func stationAvailability(_ station: ChargingStation) -> String {
        let groups = station.connectors.connectors
        let known = groups.compactMap { $0.availableCount }
        guard !known.isEmpty else { return "Availability unavailable" }
        let totals = groups.compactMap { $0.count }
        let available = known.reduce(0, +)
        return totals.count == groups.count && known.count == groups.count
            ? "\(available) of \(totals.reduce(0, +)) available" : "\(available) available"
    }

    /// e.g. "CCS2 · 60 kW, Type 2 · 22 kW"
    static func connectorSummary(_ station: ChargingStation) -> String {
        let groups = station.connectors.connectors
        guard !groups.isEmpty else { return "Connector details unavailable" }
        return groups.map { c in
            let d = ConnectorDisplay(c)
            return d.powerText.hasSuffix("kW") ? "\(d.typeText) · \(d.powerText)" : d.typeText
        }.joined(separator: ", ")
    }
}
