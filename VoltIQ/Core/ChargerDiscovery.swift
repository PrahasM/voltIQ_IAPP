import Combine
import Foundation

struct Coordinate: Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    func distance(to other: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(a)))
    }
}

struct ChargerDiscoveryConfig: Equatable {
    var radiusMeters = 5_000.0
    var resultLimit = 20
    static let `default` = ChargerDiscoveryConfig()
}

enum ConnectorType: String, Equatable, Hashable, CaseIterable {
    case ccs1, ccs2, type2, chademo, nacs, other, unknown
}

struct ChargingConnector: Identifiable, Equatable, Hashable {
    let type: ConnectorType
    let maxPowerKW: Double?
    let count: Int?

    var id: String { "\(type.rawValue)|\(maxPowerKW.map { String($0) } ?? "-")" }
}

enum ConnectorDetails: Equatable, Hashable {
    case available([ChargingConnector])
    case unavailable

    var connectors: [ChargingConnector] { if case .available(let list) = self { return list } else { return [] } }
}

struct RawConnector: Equatable {
    var type: ConnectorType
    var maxPowerKW: Double?
    var count: Int?
}

struct ChargingStation: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let distanceMeters: Double?
    let source: String
    var connectors: ConnectorDetails = .unavailable

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    var distanceText: String? {
        guard let meters = distanceMeters, meters.isFinite, meters >= 0 else { return nil }
        if meters < 1000 { return "\(Int(meters.rounded())) m away" }
        return String(format: "%.1f km away", locale: Locale(identifier: "en_US_POSIX"), meters / 1000)
    }
}

/// A provider result before validation; every field may be missing or malformed.
struct RawStation: Equatable {
    var id: String?
    var name: String?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var source: String
    /// nil means the provider supplied no connector data.
    var connectors: [RawConnector]? = nil
}

protocol ChargerProvider {
    func search(near location: Coordinate, config: ChargerDiscoveryConfig) async throws -> [RawStation]
}

enum LocationAuthorization: Equatable { case notDetermined, authorized, denied }

@MainActor protocol LocationProviding {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
    func currentLocation() async throws -> Coordinate
}

enum ChargerDiscoveryError: Error, Equatable {
    case locationUnavailable
    case network
    case provider
    case timeout

    var userMessage: String {
        switch self {
        case .locationUnavailable: return "We couldn't determine your location. Please try again."
        case .network: return "You appear to be offline. Check your connection and try again."
        case .provider: return "We couldn't load charging stations right now. Please try again."
        case .timeout: return "Looking for chargers took too long. Please try again."
        }
    }
}

enum StationNormalizer {
    static func normalize(_ raw: [RawStation], from user: Coordinate?, limit: Int) -> [ChargingStation] {
        var seen = Set<String>()
        var stations: [ChargingStation] = []
        for item in raw {
            guard let id = clean(item.id), let lat = item.latitude, let lon = item.longitude,
                  Coordinate(latitude: lat, longitude: lon).isValid, seen.insert(id).inserted else { continue }
            let coordinate = Coordinate(latitude: lat, longitude: lon)
            stations.append(ChargingStation(
                id: id, name: clean(item.name) ?? "EV charging station", latitude: lat, longitude: lon,
                address: clean(item.address), distanceMeters: user.flatMap { $0.isValid ? $0.distance(to: coordinate) : nil },
                source: item.source, connectors: connectors(item.connectors)))
        }
        stations.sort { ($0.distanceMeters ?? .infinity, $0.id) < ($1.distanceMeters ?? .infinity, $1.id) }
        return Array(stations.prefix(max(0, limit)))
    }

    /// Groups by (type, power) so e.g. CCS2 60 kW and CCS2 120 kW stay distinct; exact duplicates merge counts.
    static func connectors(_ raw: [RawConnector]?) -> ConnectorDetails {
        guard let raw, !raw.isEmpty else { return .unavailable }
        struct Key: Hashable { let type: ConnectorType; let power: Double? }
        var order: [Key] = []
        var counts: [Key: Int?] = [:]
        for item in raw {
            let power = item.maxPowerKW.flatMap { $0.isFinite && $0 > 0 ? ($0 * 10).rounded() / 10 : nil }
            let count = item.count.flatMap { $0 >= 1 ? $0 : nil }
            let key = Key(type: item.type, power: power)
            if let existing = counts[key] {
                counts[key] = (existing == nil && count == nil) ? nil : (existing ?? 0) + (count ?? 0)
            } else {
                order.append(key)
                counts[key] = .some(count)
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: ConnectorType.allCases.enumerated().map { ($1, $0) })
        let groups = order.map { ChargingConnector(type: $0.type, maxPowerKW: $0.power, count: counts[$0] ?? nil) }
            .sorted { (rank[$0.type]!, -($0.maxPowerKW ?? -1)) < (rank[$1.type]!, -($1.maxPowerKW ?? -1)) }
        return groups.isEmpty ? .unavailable : .available(groups)
    }

    private static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              !["nil", "null", "(null)"].contains(value.lowercased()) else { return nil }
        return value
    }
}

@MainActor
final class ChargerDiscoveryViewModel: ObservableObject {
    enum State: Equatable {
        case idle, requestingPermission, locating, searching
        case loaded([ChargingStation])
        case empty, permissionDenied
        case failed(String)

        var isLoading: Bool { self == .requestingPermission || self == .locating || self == .searching }
    }

    @Published private(set) var state = State.idle
    @Published private(set) var userLocation: Coordinate?
    @Published private(set) var selectedID: String?
    private let location: LocationProviding
    private let provider: ChargerProvider
    private let config: ChargerDiscoveryConfig
    private var task: Task<Void, Never>?

    init(location: LocationProviding, provider: ChargerProvider, config: ChargerDiscoveryConfig = .default) {
        self.location = location
        self.provider = provider
        self.config = config
    }

    var stations: [ChargingStation] { if case .loaded(let list) = state { return list } else { return [] } }
    var selectedStation: ChargingStation? { stations.first { $0.id == selectedID } }

    /// Starts discovery unless one is already running. Does not re-prompt after a denial.
    func load() async {
        guard !state.isLoading else { return }
        await run()
    }

    /// Explicit user retry; re-checks permission (e.g. after returning from Settings).
    func retry() async {
        guard !state.isLoading else { return }
        await run()
    }

    func select(id: String?) {
        guard let id else { selectedID = nil; return }
        if stations.contains(where: { $0.id == id }) { selectedID = id }
    }

    private func run() async {
        selectedID = nil
        var status = location.authorization
        if status == .notDetermined {
            state = .requestingPermission
            status = await location.requestAuthorization()
        }
        guard status == .authorized else { state = .permissionDenied; return }
        state = .locating
        let here: Coordinate
        do { here = try await location.currentLocation() }
        catch { state = .failed(Self.message(for: error)); return }
        guard here.isValid else { state = .failed(ChargerDiscoveryError.locationUnavailable.userMessage); return }
        userLocation = here
        state = .searching
        do {
            let raw = try await provider.search(near: here, config: config)
            let stations = StationNormalizer.normalize(raw, from: here, limit: config.resultLimit)
            state = stations.isEmpty ? .empty : .loaded(stations)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let known = error as? ChargerDiscoveryError { return known.userMessage }
        if (error as? URLError) != nil { return ChargerDiscoveryError.network.userMessage }
        return ChargerDiscoveryError.provider.userMessage
    }
}
