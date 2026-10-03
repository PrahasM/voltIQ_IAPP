import MapKit
import SwiftUI

struct RouteMapView: UIViewRepresentable {
    let route: RouteSummary
    let destinationName: String
    let destination: Coordinate
    var recenterToken = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.route != route || coordinator.token != recenterToken else { return }
        coordinator.route = route
        coordinator.token = recenterToken
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        let points = route.path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard !points.isEmpty else { return }
        let line = MKPolyline(coordinates: points, count: points.count)
        map.addOverlay(line)
        let pin = MKPointAnnotation()
        pin.coordinate = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
        pin.title = destinationName
        map.addAnnotation(pin)
        map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 48, left: 32, bottom: 48, right: 32), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var route: RouteSummary?
        var token = 0
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor.systemGreen
            renderer.lineWidth = 6
            return renderer
        }
    }
}

struct RouteView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model: RouteViewModel
    let plan: ChargePlan
    let onDone: () -> Void
    private var station: ChargingStation { plan.station }
    @State private var showSteps = false
    @State private var recenter = 0
    @State private var showStart = false
    @State private var startPercent = 20.0
    @State private var message: String?

    init(plan: ChargePlan, origin: Coordinate?, onDone: @escaping () -> Void) {
        self.plan = plan
        self.onDone = onDone
        let station = plan.station
        _model = StateObject(wrappedValue: RouteViewModel(provider: MapKitRouteProvider(), origin: origin, destination: station.coordinate))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .idle, .loading:
                VStack(spacing: 12) { ProgressView(); Text("Finding the route…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let route):
                RouteMapView(route: route, destinationName: station.name, destination: station.coordinate, recenterToken: recenter)
                    .overlay(alignment: .topTrailing) {
                        Button { recenter += 1 } label: { Image(systemName: "scope").padding(12).background(.regularMaterial, in: Circle()) }
                            .padding(12).accessibilityLabel("Recenter route")
                    }
                VStack(alignment: .leading, spacing: 8) {
                    Text(route.summaryText).font(.title3.bold())
                    Text("to \(station.name)").font(.subheadline).foregroundStyle(.secondary)
                    if !route.steps.isEmpty {
                        DisclosureGroup("Directions (\(route.steps.count) steps)", isExpanded: $showSteps) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(route.steps) { step in
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(step.instruction).font(.subheadline)
                                            Spacer()
                                            Text(RouteFormatting.distance(step.distanceMeters)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.frame(maxHeight: 200)
                        }
                    }
                }.padding(16)
            case .needsLocation:
                message("location.slash", "Your location is needed", "Allow location access in Settings, then open Chargers again to see the route.", retry: false)
            case .noRoute:
                message("road.lanes", "No route found", "We couldn't find a driving route to this station.", retry: true)
            case .failed(let text):
                message("exclamationmark.triangle", "Something went wrong", text, retry: true)
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle("Route").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $showStart) { startSheet }
    }

    private var inProgress: Bool { store.profile?.plannedSession?.status == .inProgress }

    private var actions: some View {
        VStack(spacing: 8) {
            if inProgress { Text("A charge is already in progress. Complete or cancel it from History first.").font(.caption).foregroundStyle(.secondary) }
            if let message { Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
            Button { startPercent = store.profile?.preferences.current ?? 20; showStart = true } label: { Label("I've arrived, start session", systemImage: "bolt.fill") }
                .buttonStyle(PrimaryButton()).disabled(inProgress)
            Button { savePlan() } label: { Label("Save plan for later", systemImage: "bookmark.fill") }
                .buttonStyle(PrimaryButton()).disabled(inProgress)
        }.padding(16).background(.regularMaterial)
    }

    private var startSheet: some View {
        NavigationStack {
            Page {
                Card {
                    Text(station.name).font(.headline)
                    NumberField(title: "Starting charge", value: $startPercent, suffix: "%")
                    Text("voltIQ only records that charging began. It doesn't start the charger or take payment.").font(.caption).foregroundStyle(.secondary)
                    if let message { Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                }
                Button("Start session") { startSession() }.buttonStyle(PrimaryButton())
            }.navigationTitle("Start session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showStart = false } } }
        }.presentationDetents([.medium])
    }

    private func savePlan() {
        do { try store.planCharge(plan); message = nil; onDone() } catch { message = error.localizedDescription }
    }

    private func startSession() {
        do { try store.planCharge(plan, startPercent: startPercent); message = nil; showStart = false; onDone() } catch { message = error.localizedDescription }
    }

    private func message(_ icon: String, _ title: String, _ detail: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if retry { Button("Retry") { Task { await model.load() } }.buttonStyle(PrimaryButton()).padding(.top, 8) }
        }.padding(24).frame(maxWidth: 420).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
