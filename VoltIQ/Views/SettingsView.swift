import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingOperator: ChargingOperator?
    @State private var deletingOperator: ChargingOperator?
    private var profile: UserProfile { store.profile ?? UserProfile(name: "") }
    var body: some View {
        Page {
            Card {
                Label("Appearance", systemImage: "circle.lefthalf.filled").font(.headline)
                Toggle("Override system appearance", isOn: Binding(get: { profile.preferences.appearance != .system }, set: { enabled in
                    store.updateProfile { $0.preferences.appearance = enabled ? .dark : .system }
                })).frame(minHeight: 48)
                if profile.preferences.appearance != .system {
                    HStack {
                        ForEach([Appearance.light, .dark]) { appearance in
                            Chip(title: appearance.label, selected: profile.preferences.appearance == appearance) { store.updateProfile { $0.preferences.appearance = appearance } }
                        }
                    }
                }
                Text("System follows your iPhone's Light / Dark setting.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label("Charging efficiency", systemImage: "leaf.fill").font(.headline)
                efficiencyControl(.dc, keyPath: \.dcEfficiency, fallback: 92)
                efficiencyControl(.ac, keyPath: \.acEfficiency, fallback: 87)
                Text("Log at least 3 valid charges of a type to learn real efficiency. Samples outside 50–100% are excluded.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label("Your car", systemImage: "car.fill").font(.headline)
                NumberField(title: "Car max AC power", value: store.setting(\.maxACPower, fallback: 11), suffix: "kW")
                NumberField(title: "Car max DC power", value: store.setting(\.maxDCPower, fallback: 150), suffix: "kW")
                Picker("My car's connector", selection: store.carConnector()) {
                    Text("Not set").tag(ConnectorType?.none)
                    ForEach([ConnectorType.ccs2, .ccs1, .type2, .chademo, .nacs], id: \.self) { type in
                        Text(ConnectorDisplay(ChargingConnector(type: type, maxPowerKW: nil, count: nil)).typeText).tag(ConnectorType?.some(type))
                    }
                }.frame(minHeight: 48)
                Text("Used by Chargers to prefer connectors that fit your car. Not set shows every connector without filtering.").font(.caption).foregroundStyle(.secondary)
                Text("Power limits must be 1–1000 kW. Effective power is the lower of the charger and car limits.").font(.caption).foregroundStyle(.secondary)
                HStack { Text("DC power above 80%"); Spacer(); Text("\(Display.number(profile.settings.taperPercent, digits: 0))%").monospacedDigit() }
                Slider(value: store.setting(\.taperPercent, fallback: 40), in: 10...100, step: 1).frame(minHeight: 48).accessibilityLabel("DC taper power percent")
                Text("DC slows down above 80% to this fraction of effective power. AC does not taper.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label("Charging operators", systemImage: "building.2.fill").font(.headline)
                if profile.operators.isEmpty { Text("Save the networks you use, then choose one on the Calculator.").foregroundStyle(.secondary) }
                ForEach(profile.operators) { op in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(op.name).font(.headline)
                        Text("\(Display.money(op.rate)) / kWh · \(op.gstIncluded ? "incl. GST" : "+18% GST")").font(.subheadline).monospacedDigit()
                        Text("Session \(Display.money(op.sessionFee)) · idle \(Display.money(op.idleFee))/min").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button { editingOperator = op } label: { Label("Edit", systemImage: "pencil").frame(minWidth: 80, minHeight: 48) }
                            Spacer()
                            Button(role: .destructive) { deletingOperator = op } label: { Label("Delete", systemImage: "trash").frame(minWidth: 80, minHeight: 48) }
                        }
                    }
                    Divider()
                }
                Button { editingOperator = ChargingOperator() } label: { Label("Add operator", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48) }
            }
            Text("Settings are saved for \(profile.name) on this device.").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editingOperator) { OperatorFormView(op: $0) }
        .alert("Delete operator?", isPresented: Binding(get: { deletingOperator != nil }, set: { if !$0 { deletingOperator = nil } })) {
            Button("Delete", role: .destructive) { if let op = deletingOperator { store.deleteOperator(op.id) }; deletingOperator = nil }
            Button("Cancel", role: .cancel) { deletingOperator = nil }
        } message: { Text("Existing charge logs keep their recorded operator and fees.") }
    }

    private func efficiencyControl(_ type: ChargerType, keyPath: WritableKeyPath<CarSettings, Double>, fallback: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("\(type.label) efficiency"); Spacer(); Text("\(Display.number(profile.settings[keyPath: keyPath], digits: 0))%").monospacedDigit() }
            Slider(value: store.setting(keyPath, fallback: fallback), in: 50...100, step: 1).frame(minHeight: 48).accessibilityLabel("\(type.label) charging efficiency")
            if let learned = LearnedEfficiency.compute(profile.entries, type: type) {
                Toggle("Use learned \(type.label): \(Display.number(learned.average * 100))% (\(learned.count) charges)", isOn: type == .ac ? store.preference(\.learnAC, fallback: false) : store.preference(\.learnDC, fallback: false)).frame(minHeight: 48)
            }
        }
    }
}

private struct OperatorFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var op: ChargingOperator
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Page {
                Card {
                    TextField("Operator name", text: $op.name).padding(.horizontal, 14).frame(minHeight: 48)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    NumberField(title: "Rate", value: $op.rate, suffix: "₹/kWh")
                    Toggle("Rate includes GST", isOn: $op.gstIncluded).frame(minHeight: 48)
                    NumberField(title: "Session fee", value: $op.sessionFee, suffix: "₹")
                    NumberField(title: "Idle fee", value: $op.idleFee, suffix: "₹/min")
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Save operator") {
                        if let validation = op.validationError { error = validation; return }
                        op.name = op.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.saveOperator(op)
                        if store.storageError == nil { dismiss() }
                    }.buttonStyle(PrimaryButton())
                }
            }.navigationTitle("Operator").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48) }
            }
        }
    }
}
