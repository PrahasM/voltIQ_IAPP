import MapKit
import SwiftUI

struct RouteMapView: UIViewRepresentable {
    let route: RouteSummary
    let destinationName: String
    let destination: Coordinate

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
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
    @StateObject private var model: RouteViewModel
    let station: ChargingStation
    @State private var showSteps = false

    init(station: ChargingStation, origin: Coordinate?) {
        self.station = station
        _model = StateObject(wrappedValue: RouteViewModel(provider: MapKitRouteProvider(), origin: origin, destination: station.coordinate))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .idle, .loading:
                VStack(spacing: 12) { ProgressView(); Text("Finding the route…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let route):
                RouteMapView(route: route, destinationName: station.name, destination: station.coordinate)
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
        .navigationTitle("Route").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
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
