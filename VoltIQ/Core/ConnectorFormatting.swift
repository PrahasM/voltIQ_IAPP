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
