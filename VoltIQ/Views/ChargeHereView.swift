import MapKit
import SwiftUI

struct ChargeHereView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let station: ChargingStation
    @State private var chosenID: String?

    private var plan: ChargePlan {
        let profile = store.profile
        return ChargePlanner.plan(station: station, carConnector: profile?.settings.connectorType, prefs: profile?.preferences ?? Preferences(),
                                  settings: profile?.settings ?? CarSettings(), efficiency: { profile?.efficiency(for: $0) ?? 0.9 }, chosenID: chosenID)
    }

    var body: some View {
        let plan = plan
        NavigationStack {
            Page {
                Card {
                    Text(station.name).font(.title3.bold())
                    if let distance = station.distanceText { Text(distance) }
                    if let address = station.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                    Text(String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), station.latitude, station.longitude))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Card {
                    Label("Connector", systemImage: "powerplug.fill").font(.headline)
                    if plan.connectors.isEmpty { Text("Connector details unavailable").foregroundStyle(.secondary) }
                    ForEach(plan.connectors) { item in connectorRow(item, selected: item.id == plan.selectedID) }
                    if plan.selectedID == nil { Text("No available compatible connector. Choose another connector or station.").font(.caption).foregroundStyle(.secondary) }
                }
                Card {
                    Label("Details", systemImage: "list.bullet.rectangle").font(.headline)
                    DetailRow(title: "Provider", value: StationFormatting.provider(station.operatorName))
                    DetailRow(title: "Price", value: StationFormatting.price(station.pricePerKWh))
                    DetailRow(title: "Session / parking fee", value: "Unavailable")
                    if let estimate = plan.estimate {
                        DetailRow(title: "Estimated time", value: Display.duration(estimate.hours))
                        DetailRow(title: "Estimated cost", value: Display.money(estimate.cost))
                        Text("To \(Display.number(estimate.targetPercent, digits: 0))%, " + (estimate.rateSource == .station
                             ? "at the station's \(StationFormatting.price(estimate.rate))."
                             : "based on your saved rate \(StationFormatting.price(estimate.rate)); the station's price is unavailable."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let note = plan.estimateNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("voltIQ doesn't start charging sessions or take payments yet. Confirming opens the next step outside the app.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { confirm(plan.handoff) } label: { Label(buttonTitle(plan.handoff), systemImage: icon(plan.handoff)) }.buttonStyle(PrimaryButton())
            }
            .navigationTitle("Charge here").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func connectorRow(_ item: PlannedConnector, selected: Bool) -> some View {
        let display = ConnectorDisplay(item.connector)
        return Button { chosenID = item.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.typeText).font(.subheadline.weight(.semibold))
                    Text(display.powerText + (display.countText.map { " · \($0)" } ?? "")).font(.caption)
                    Text(StationFormatting.availability(item.connector)).font(.caption).foregroundStyle(.secondary)
                    if item.compatibility == .incompatible { Text("Not your car's connector").font(.caption).foregroundStyle(.orange) }
                    if item.compatibility == .unknown { Text("Compatibility unavailable").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }.frame(minHeight: 48)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func buttonTitle(_ handoff: ChargeHandoff) -> String {
        if case .providerApp = handoff { return "Confirm & open provider app" }
        return "Confirm & get directions"
    }

    private func icon(_ handoff: ChargeHandoff) -> String {
        if case .providerApp = handoff { return "arrow.up.forward.app" }
        return "location.fill"
    }

    private func confirm(_ handoff: ChargeHandoff) {
        switch handoff {
        case .providerApp(let url): openURL(url)
        case .directions(let c):
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)))
            item.name = station.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        }
    }
}
