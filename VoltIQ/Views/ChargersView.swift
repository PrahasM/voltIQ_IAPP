import MapKit
import SwiftUI
import UIKit

struct ChargersView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: ChargerDiscoveryViewModel
    @State private var chargeStation: ChargingStation?
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20.5937, longitude: 78.9629),
                                                   span: MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 25))

    init(model: ChargerDiscoveryViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ChargerDiscoveryViewModel(location: CoreLocationService(), provider: ChargerProviderFactory.make()))
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: model.stations) { station in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)) {
                    Button { model.select(id: station.id) } label: {
                        Image(systemName: "bolt.circle.fill").font(.title)
                            .foregroundStyle(model.selectedID == station.id ? Color.orange : VoltTheme.accent(scheme))
                            .scaleEffect(model.selectedID == station.id ? 1.3 : 1)
                            .frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel(station.name)
                }
            }.frame(height: 280)
            if let station = model.selectedStation { ConnectorsCard(station: station, chargeHere: { chargeStation = station }).padding(.horizontal, 20).padding(.top, 12) }
            content
        }
        .background(VoltTheme.background(scheme).ignoresSafeArea())
        .sheet(item: $chargeStation) { ChargeHereView(station: $0) }
        .task { await model.load() }
        .onChange(of: scenePhase) { phase in if phase == .active, model.state == .permissionDenied { retry() } }
        .onChange(of: model.userLocation) { if let here = $0 { center(here, span: 0.06) } }
        .onChange(of: model.selectedID) { id in
            if let station = model.selectedStation, id != nil { center(station.coordinate, span: 0.02) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .requestingPermission, .locating, .searching:
            VStack(spacing: 12) { ProgressView(); Text(loadingText).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let stations):
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) { ForEach(stations) { row($0) } }.padding(20)
                }.onChange(of: model.selectedID) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        case .empty:
            message("mappin.slash", "No EV charging stations found nearby.", "Try again from a different location.", button: ("Refresh", retry))
        case .permissionDenied:
            message("location.slash", "Location access is needed",
                    "voltIQ uses your location only to find EV chargers near you. Allow location access in Settings to continue.",
                    button: ("Open Settings", openSettings))
        case .failed(let text):
            message("exclamationmark.triangle", "Something went wrong", text, button: ("Retry", retry))
        }
    }

    private var loadingText: String {
        switch model.state {
        case .requestingPermission: return "Waiting for location permission…"
        case .locating: return "Finding your location…"
        default: return "Searching for chargers…"
        }
    }

    private func row(_ station: ChargingStation) -> some View {
        let selected = model.selectedID == station.id
        return Button { model.select(id: station.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name).font(.headline)
                if let distance = station.distanceText { Text(distance).font(.subheadline).foregroundStyle(VoltTheme.accent(scheme)) }
                if let address = station.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                Text(StationFormatting.connectorSummary(station)).font(.caption)
                Text("\(StationFormatting.stationAvailability(station)) · \(StationFormatting.provider(station.operatorName)) · \(StationFormatting.price(station.pricePerKWh))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(VoltTheme.card(scheme), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? VoltTheme.accent(scheme) : .clear, lineWidth: 2))
        }.buttonStyle(.plain).id(station.id).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func message(_ icon: String, _ title: String, _ detail: String, button: (String, () -> Void)) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button.0, action: button.1).buttonStyle(PrimaryButton()).padding(.top, 8)
        }.padding(24).frame(maxWidth: 420).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retry() { Task { await model.retry() } }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
    private func center(_ c: Coordinate, span: Double) {
        withAnimation { region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)) }
    }
}

private struct ConnectorsCard: View {
    let station: ChargingStation
    let chargeHere: () -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name).font(.headline)
                if let distance = station.distanceText { Text(distance).font(.subheadline) }
                if let address = station.address { Text(address).font(.caption).foregroundStyle(.secondary) }
            }
            Text("CONNECTORS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            switch station.connectors {
            case .unavailable:
                Text("Connector details unavailable").foregroundStyle(.secondary)
            case .available(let list):
                ForEach(list) { connector in
                    let display = ConnectorDisplay(connector)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.typeText).font(.subheadline.weight(.semibold))
                        Text(display.powerText.hasSuffix("kW") ? "⚡ \(display.powerText)" : display.powerText).monospacedDigit()
                        if let count = display.countText { Text(count).font(.caption).foregroundStyle(.secondary) }
                        Text([StationFormatting.availability(connector), StationFormatting.updated(connector.availabilityUpdated)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button(action: chargeHere) { Label("Charge Here", systemImage: "bolt.fill") }.buttonStyle(PrimaryButton())
        }.id("connectors-\(station.id)")
    }
}
