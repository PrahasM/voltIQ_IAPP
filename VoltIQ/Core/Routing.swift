import Combine
import Foundation

struct RouteStep: Equatable, Identifiable {
    let id: Int
    let instruction: String
    let distanceMeters: Double
}

struct RouteSummary: Equatable {
    let distanceMeters: Double
    let travelSeconds: Double
    let path: [Coordinate]
    let steps: [RouteStep]

    var summaryText: String { "\(RouteFormatting.duration(travelSeconds)) · \(RouteFormatting.distance(distanceMeters))" }
}

protocol RouteProviding {
    func route(from origin: Coordinate, to destination: Coordinate) async throws -> RouteSummary
}

enum RouteError: Error, Equatable { case noRoute, network, provider }

enum RouteFormatting {
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 1 { return "Under 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func distance(_ meters: Double) -> String {
        let m = max(0, meters)
        if m < 1000 { return "\(Int((m / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), m / 1000)
    }
}

@MainActor
final class RouteViewModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, loaded(RouteSummary), noRoute, needsLocation
        case failed(String)
    }

    @Published private(set) var state = State.idle
    private let provider: RouteProviding
    private let origin: Coordinate?
    private let destination: Coordinate

    init(provider: RouteProviding, origin: Coordinate?, destination: Coordinate) {
        self.provider = provider
        self.origin = origin
        self.destination = destination
    }

    func load() async {
        guard state != .loading else { return }
        guard let origin, origin.isValid, destination.isValid else { state = .needsLocation; return }
        state = .loading
        do {
            state = .loaded(try await provider.route(from: origin, to: destination))
        } catch RouteError.noRoute {
            state = .noRoute
        } catch RouteError.network, is URLError {
            state = .failed("You appear to be offline. Check your connection and try again.")
        } catch {
            state = .failed("We couldn't get a route right now. Please try again.")
        }
    }
}
