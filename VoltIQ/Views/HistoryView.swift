import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showLog = false
    @State private var showExport = false
    @State private var confirmClear = false
    @State private var deleting: ChargeEntry?
    @State private var receipt: ReceiptSelection?
    @State private var exportError: String?
    private var entries: [ChargeEntry] { store.profile?.entries ?? [] }
    private var spent: Double { entries.reduce(0) { $0 + $1.spent } }
    private var energy: Double { entries.reduce(0) { $0 + $1.energy } }

    var body: some View {
        Page {
            Card {
                Text("Your charging story").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                    metric("Total spent", Display.money(spent), "indianrupeesign.circle")
                    metric("Battery energy", "\(Display.number(energy)) kWh", "battery.75percent")
                    metric("Sessions", "\(entries.count)", "bolt.circle")
                    metric("Avg ₹ / kWh", energy > 0 ? Display.money(spent / energy) : "—", "chart.bar")
                }
                Text("Average uses battery energy added, matching the web history. Each entry also shows its rate per billed kWh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { showLog = true } label: { Label("Add a charge", systemImage: "plus.circle.fill") }.buttonStyle(PrimaryButton())
            if entries.isEmpty {
                Card {
                    Label("A fresh start", systemImage: "clock").font(.headline)
                    Text("Log your first charge to track costs and learn your car's real efficiency.").foregroundStyle(.secondary)
                }
            }
            ForEach(entries.reversed()) { entry in
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.operatorName ?? "Charge session").font(.headline)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Display.money(entry.spent)).font(.headline).monospacedDigit()
                    }
                    if let billed = entry.billed { DetailRow(title: "Energy billed", value: "\(Display.number(billed)) kWh") }
                    DetailRow(title: "Battery energy", value: "\(Display.number(entry.energy)) kWh")
                    if let start = entry.start, let end = entry.end { DetailRow(title: "Charge", value: "\(Display.number(start))→\(Display.number(end))%") }
                    DetailRow(title: "Charger", value: [entry.type?.label, entry.chargerPower.map { "\(Display.number($0)) kW" }].compactMap { $0 }.joined(separator: " · "))
                    DetailRow(title: "Rate · \(entry.gst.label)", value: "\(Display.money(entry.rate)) / kWh")
                    if let efficiency = entry.efficiency { DetailRow(title: "Real efficiency", value: "\(Display.number(efficiency * 100))%") }
                    if let rate = entry.effectiveRate { DetailRow(title: "Effective incl. fees", value: "\(Display.money(rate)) / kWh") }
                    if let fees = entry.fees { DetailRow(title: "Session + idle fees", value: Display.money(fees)) }
                    if let idle = entry.idleMinutes { DetailRow(title: "Idle time", value: "\(Display.number(idle)) min") }
                    if let odometer = entry.odometer { DetailRow(title: "Odometer", value: "\(Display.number(odometer)) km") }
                    HStack {
                        if let url = store.receiptURL(entry) {
                            Button { receipt = ReceiptSelection(url: url) } label: { Label("Receipt", systemImage: "photo").frame(minHeight: 48) }
                        }
                        Spacer()
                        Button(role: .destructive) { deleting = entry } label: { Label("Delete", systemImage: "trash").frame(minWidth: 80, minHeight: 48) }
                    }
                }
            }
            if !entries.isEmpty {
                Card {
                    Button { showExport = true } label: { Label("Export CSV", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48) }
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear history", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 48) }
                    Text("Up to 500 sessions per driver. Receipt photos stay in this app's local storage.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showLog, onDismiss: { NotificationCenter.default.post(name: .chargeFormDismissed, object: nil) }) { ChargeFormView(draft: ChargeDraft()) }
        .sheet(item: $receipt) { selection in ReceiptView(url: selection.url) }
        .fileExporter(isPresented: $showExport, document: CSVDocument(text: ChargeCSV.export(entries)), contentType: .commaSeparatedText,
                      defaultFilename: "voltiq-\(store.profile?.name ?? "history")") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .alert("Delete charge?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { store.deleteEntry(deleting.timestamp) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This charge and its receipt photo will be removed from this device.") }
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All charges and receipt photos for \(store.profile?.name ?? "this driver") will be deleted.") }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }
}

private struct ReceiptSelection: Identifiable { let url: URL; var id: URL { url } }

private struct ReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 700).padding()
                } else { Label("Receipt photo could not be read.", systemImage: "photo").padding() }
            }.navigationTitle("Receipt").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 48) } }
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
