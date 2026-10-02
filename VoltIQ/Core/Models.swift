import Foundation

enum ChargerType: String, Codable, CaseIterable, Identifiable {
    case ac, dc
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum CalculationMode: String, Codable, CaseIterable, Identifiable {
    case target, amount, time
    var id: String { rawValue }
    var label: String {
        switch self {
        case .target: return "Target %"
        case .amount: return "₹ amount"
        case .time: return "Time"
        }
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum GSTTreatment: Int, Codable {
    case none = 0, included = 1, added = 2
    var label: String {
        switch self {
        case .none: return "no GST"
        case .included: return "incl. GST"
        case .added: return "+18% GST"
        }
    }
}

struct ChargerPreset: Identifiable {
    let id: String
    let power: Double
    let type: ChargerType
    let name: String
    static let all: [ChargerPreset] = [
        .init(id: "ac3.3", power: 3.3, type: .ac, name: "Home"),
        .init(id: "ac7.2", power: 7.2, type: .ac, name: "Wallbox"),
        .init(id: "ac11", power: 11, type: .ac, name: "3-phase"),
        .init(id: "ac22", power: 22, type: .ac, name: "Fast AC"),
        .init(id: "dc30", power: 30, type: .dc, name: "Fast"),
        .init(id: "dc60", power: 60, type: .dc, name: "Fast"),
        .init(id: "dc120", power: 120, type: .dc, name: "Rapid"),
        .init(id: "dc180", power: 180, type: .dc, name: "Ultra")
    ]
}

struct Preferences: Codable, Equatable {
    var capacity = 79.0
    var current = 42.0
    var target = 85.0
    var customTarget = false
    var mode = CalculationMode.target
    var budget = 500.0
    var minutes = 30.0
    var rate = 25.0
    var gstIncluded = true
    var chargerID = "dc60"
    var customPower = 60.0
    var customType = ChargerType.dc
    var operatorID: String?
    var learnAC = false
    var learnDC = false
    var appearance = Appearance.system

    var chargerPower: Double { preset?.power ?? customPower }
    var chargerType: ChargerType { preset?.type ?? customType }
    private var preset: ChargerPreset? { ChargerPreset.all.first { $0.id == chargerID } }
    var gstTreatment: GSTTreatment { gstIncluded ? .included : (operatorID == nil ? .none : .added) }
}

struct CarSettings: Codable, Equatable {
    var dcEfficiency = 92.0
    var acEfficiency = 87.0
    var maxACPower = 11.0
    var maxDCPower = 150.0
    var taperPercent = 40.0
}

struct ChargingOperator: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var rate = 25.0
    var gstIncluded = true
    var sessionFee = 0.0
    var idleFee = 0.0

    enum CodingKeys: String, CodingKey { case id, name = "n", rate = "r", gstIncluded = "g", sessionFee = "s", idleFee = "f" }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        rate = try values.decode(Double.self, forKey: .rate)
        gstIncluded = try values.decode(Int.self, forKey: .gstIncluded) == 1
        sessionFee = try values.decodeIfPresent(Double.self, forKey: .sessionFee) ?? 0
        idleFee = try values.decodeIfPresent(Double.self, forKey: .idleFee) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(rate, forKey: .rate)
        try values.encode(gstIncluded ? 1 : 0, forKey: .gstIncluded)
        try values.encode(sessionFee, forKey: .sessionFee)
        try values.encode(idleFee, forKey: .idleFee)
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an operator name." }
        if !rate.isFinite || !(0.01...200).contains(rate) { return "Rate must be ₹0.01–₹200 / kWh." }
        if !sessionFee.isFinite || !idleFee.isFinite || sessionFee < 0 || idleFee < 0 { return "Fees must be zero or greater." }
        return nil
    }
}

struct ChargeEntry: Codable, Equatable, Identifiable {
    var timestamp: Double
    var energy: Double
    var cost: Double
    var rate: Double
    var gst: GSTTreatment
    var chargerPower: Double?
    var billed: Double?
    var start: Double?
    var end: Double?
    var type: ChargerType?
    var operatorName: String?
    var operatorID: String?
    var odometer: Double?
    var idleMinutes: Double?
    var fees: Double?
    var efficiency: Double?
    var effectiveRate: Double?
    var photo: Int?
    var id: Double { timestamp }
    var date: Date { Date(timeIntervalSince1970: timestamp / 1000) }
    var spent: Double { cost + (fees ?? 0) }

    enum CodingKeys: String, CodingKey {
        case timestamp = "t", energy = "e", cost = "c", rate = "r", gst = "g", chargerPower = "k"
        case billed = "b", start = "s", end = "f", type = "y", operatorName = "o", operatorID = "oi"
        case odometer = "d", idleMinutes = "m", fees = "fe", efficiency = "x", effectiveRate = "q", photo = "p"
    }

    init(timestamp: Double, energy: Double, cost: Double, rate: Double, gst: GSTTreatment, chargerPower: Double?) {
        self.timestamp = timestamp
        self.energy = energy
        self.cost = cost
        self.rate = rate
        self.gst = gst
        self.chargerPower = chargerPower
    }

    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try v.decode(Double.self, forKey: .timestamp)
        energy = try v.decode(Double.self, forKey: .energy)
        cost = try v.decode(Double.self, forKey: .cost)
        rate = try v.decode(Double.self, forKey: .rate)
        gst = try v.decode(GSTTreatment.self, forKey: .gst)
        chargerPower = try? v.decode(Double.self, forKey: .chargerPower)
        billed = try v.decodeIfPresent(Double.self, forKey: .billed)
        start = try v.decodeIfPresent(Double.self, forKey: .start)
        end = try v.decodeIfPresent(Double.self, forKey: .end)
        type = try v.decodeIfPresent(ChargerType.self, forKey: .type)
        operatorName = try v.decodeIfPresent(String.self, forKey: .operatorName)
        operatorID = try v.decodeIfPresent(String.self, forKey: .operatorID)
        odometer = try v.decodeIfPresent(Double.self, forKey: .odometer)
        idleMinutes = try v.decodeIfPresent(Double.self, forKey: .idleMinutes)
        fees = try v.decodeIfPresent(Double.self, forKey: .fees)
        efficiency = try v.decodeIfPresent(Double.self, forKey: .efficiency)
        effectiveRate = try v.decodeIfPresent(Double.self, forKey: .effectiveRate)
        photo = try v.decodeIfPresent(Int.self, forKey: .photo)
    }
}

struct LearnedEfficiency {
    let average: Double
    let count: Int
    static func compute(_ entries: [ChargeEntry], type: ChargerType) -> LearnedEfficiency? {
        let values = entries.filter { $0.type == type }.compactMap(\.efficiency).filter { $0.isFinite && (0.5...1).contains($0) }
        guard values.count >= 3 else { return nil }
        return .init(average: values.reduce(0, +) / Double(values.count), count: values.count)
    }
}

struct UserProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var preferences = Preferences()
    var settings = CarSettings()
    var operators: [ChargingOperator] = []
    var entries: [ChargeEntry] = []

    static func normalize(_ name: String) -> String {
        String(name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(24))
    }

    func efficiency(for type: ChargerType) -> Double {
        let enabled = type == .ac ? preferences.learnAC : preferences.learnDC
        if enabled, let learned = LearnedEfficiency.compute(entries, type: type) { return learned.average }
        return (type == .ac ? settings.acEfficiency : settings.dcEfficiency) / 100
    }
}

struct DeviceState: Codable {
    var version = 1
    var selectedUserID: UUID?
    var users: [UserProfile] = []
}
