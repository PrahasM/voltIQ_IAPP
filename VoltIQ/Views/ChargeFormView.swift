import PhotosUI
import SwiftUI
import UIKit

struct ChargeFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: ChargeDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var receiptData: Data?
    @State private var loadingPhoto = false
    @State private var error: String?

    private var op: ChargingOperator? { store.profile?.operators.first { $0.id == draft.operatorID } }
    private var preview: ChargeEntry? {
        try? draft.entry(capacity: store.profile?.preferences.capacity ?? 79, operator: op,
                         manualGST: store.profile?.preferences.gstIncluded == true ? .included : .none)
    }

    var body: some View {
        NavigationStack {
            Page {
                Text("Enter the values from your charger or receipt. Correct any estimates before saving.").font(.subheadline).foregroundStyle(.secondary)
                Card {
                    DatePicker("Date & time", selection: $draft.date).frame(minHeight: 48)
                    Picker("Operator", selection: Binding(get: { draft.operatorID ?? "" }, set: { id in
                        draft.operatorID = id.isEmpty ? nil : id
                        if let selected = store.profile?.operators.first(where: { $0.id == id }) { draft.rate = selected.rate }
                    })) {
                        Text("No operator").tag("")
                        ForEach(store.profile?.operators ?? []) { op in Text(op.name).tag(op.id) }
                    }.pickerStyle(.menu).frame(minHeight: 48)
                    HStack {
                        ForEach(ChargerType.allCases) { type in Chip(title: type.label, selected: draft.type == type) { draft.type = type } }
                    }
                    OptionalNumberField(title: "Charger power (kW, optional)", value: $draft.power)
                    OptionalNumberField(title: "Start %", value: $draft.start)
                    OptionalNumberField(title: "End %", value: $draft.end)
                    OptionalNumberField(title: "kWh billed", value: $draft.billed)
                    OptionalNumberField(title: "Amount paid (₹, before separate fees)", value: $draft.amount)
                    OptionalNumberField(title: "Rate (₹/kWh, optional)", value: $draft.rate)
                    OptionalNumberField(title: "Idle minutes (optional)", value: $draft.idle)
                    OptionalNumberField(title: "Odometer km (optional)", value: $draft.odometer)
                    if let op { Text("Fees: \(Display.money(op.sessionFee)) session + \(Display.money(op.idleFee))/idle minute. Don't include these twice in amount paid.").font(.caption).foregroundStyle(.secondary) }
                }
                Card {
                    Label("Log preview", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                    if let preview {
                        DetailRow(title: "Real efficiency", value: "\(Display.number((preview.efficiency ?? 0) * 100))%")
                        DetailRow(title: "Effective ₹ / kWh", value: Display.money(preview.effectiveRate ?? 0))
                        DetailRow(title: "Fees", value: Display.money(preview.fees ?? 0))
                        DetailRow(title: "Total spent", value: Display.money(preview.spent))
                    } else { Text("Fill in start %, end %, kWh billed and amount paid.").foregroundStyle(.secondary) }
                }
                Card {
                    Label("Receipt photo", systemImage: "doc.text").font(.headline)
                    if let receiptData, let image = UIImage(data: receiptData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                        Button(role: .destructive) { self.receiptData = nil; photoItem = nil } label: { Label("Remove photo", systemImage: "trash").frame(minHeight: 48) }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose receipt", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 48)
                    }.disabled(loadingPhoto)
                    if loadingPhoto { ProgressView("Loading receipt…") }
                    Text("Stored only on this device as a compressed JPEG. Photos stored only in iCloud must be downloaded first.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                Button("Save charge") {
                    do { try store.saveCharge(draft, receipt: receiptData); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryButton()).disabled(loadingPhoto)
            }.navigationTitle("Log a charge").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48) } }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            loadingPhoto = true
            Task { @MainActor in
                defer { loadingPhoto = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                          let compressed = ReceiptImage.compress(image) else { throw CalculationError.invalid("Couldn't read this photo. Choose another image.") }
                    receiptData = compressed
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

private enum ReceiptImage {
    static func compress(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1280 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
