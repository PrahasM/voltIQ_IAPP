import SwiftUI
import UIKit

struct CalculatorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showLog = false
    @State private var copied = false
    private var prefs: Preferences { store.profile?.preferences ?? Preferences() }

    var body: some View {
        Page {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to charge, \(store.profile?.name ?? "")?").font(.title2.bold())
                    Text("Plan your next stop. Every calculation stays on this device.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "leaf.fill").font(.title).foregroundStyle(.tint).accessibilityHidden(true)
            }
            Card {
                Text("YOUR BATTERY").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                NumberField(title: "Battery capacity", value: store.preference(\.capacity, fallback: 79), suffix: "kWh")
                Text("Current charge").font(.subheadline.weight(.medium))
                HStack(spacing: 12) {
                    Button { stepCurrent(-1) } label: { Image(systemName: "minus").frame(width: 48, height: 48).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) }
                        .accessibilityLabel("Decrease current charge by 1 percent")
                    NumberField(title: "Current %", value: store.preference(\.current, fallback: 42), suffix: "%")
                    Button { stepCurrent(1) } label: { Image(systemName: "plus").frame(width: 48, height: 48).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) }
                        .accessibilityLabel("Increase current charge by 1 percent")
                }.buttonStyle(.plain)
                Text("Calculate by").font(.subheadline.weight(.medium))
                ViewThatFits(in: .horizontal) {
                    HStack { modeChips }
                    VStack { modeChips }
                }
                switch prefs.mode {
                case .target:
                    Text("Target charge").font(.subheadline.weight(.medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                        ForEach([80.0, 85, 90, 100], id: \.self) { value in
                            Chip(title: "\(Int(value))%", selected: !prefs.customTarget && prefs.target == value) {
                                store.updateProfile { $0.preferences.target = value; $0.preferences.customTarget = false }
                            }
                        }
                        Chip(title: "Custom", selected: prefs.customTarget) { store.updateProfile { $0.preferences.customTarget = true } }
                    }
                    if prefs.customTarget { NumberField(title: "Custom target", value: store.preference(\.target, fallback: 85), suffix: "%") }
                case .amount:
                    NumberField(title: "Amount to spend", value: store.preference(\.budget, fallback: 500), suffix: "₹")
                case .time:
                    NumberField(title: "Charging time", value: store.preference(\.minutes, fallback: 30), suffix: "min")
                }
            }
            Card {
                Text("AT THE CHARGER").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Picker("Operator", selection: Binding(get: { prefs.operatorID ?? "" }, set: { store.selectOperator($0.isEmpty ? nil : $0) })) {
                    Text("Manual rate").tag("")
                    ForEach(store.profile?.operators ?? []) { op in Text(op.name).tag(op.id) }
                }.pickerStyle(.menu).frame(minHeight: 48)
                HStack {
                    Text("Rate").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Display.money(prefs.rate)) / kWh").font(.headline).monospacedDigit()
                }
                Slider(value: Binding(get: { prefs.rate }, set: { store.setRate($0) }), in: min(5, prefs.rate)...max(40, prefs.rate), step: 0.5)
                    .frame(minHeight: 48).accessibilityLabel("Rate in rupees per kWh").accessibilityValue(Display.money(prefs.rate))
                HStack { Text(Display.money(min(5, prefs.rate))); Spacer(); Text(Display.money(max(40, prefs.rate))) }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Toggle(prefs.operatorID == nil ? "Include 18% GST" : "Rate includes 18% GST", isOn: store.preference(\.gstIncluded, fallback: true)).frame(minHeight: 48)
                Text(prefs.gstTreatment.label).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text("Charger power").font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 10) {
                    ForEach(ChargerPreset.all) { preset in
                        Chip(title: "\(Display.number(preset.power)) kW · \(preset.type.label)", subtitle: preset.name, selected: prefs.chargerID == preset.id) {
                            store.updateProfile { $0.preferences.chargerID = preset.id }
                        }
                    }
                    Chip(title: "Custom", subtitle: "Set kW & type", selected: prefs.chargerID == "custom") { store.updateProfile { $0.preferences.chargerID = "custom" } }
                }
                if prefs.chargerID == "custom" {
                    NumberField(title: "Charger power", value: store.preference(\.customPower, fallback: 60), suffix: "kW")
                    HStack {
                        ForEach(ChargerType.allCases) { type in
                            Chip(title: type.label, selected: prefs.customType == type) { store.updateProfile { $0.preferences.customType = type } }
                        }
                    }
                }
            }
            switch store.result {
            case .success(let result):
                ResultCard(result: result, prefs: prefs, op: store.selectedOperator, copied: $copied)
                Button { showLog = true } label: { Label("Log this charge", systemImage: "plus.circle.fill") }.buttonStyle(PrimaryButton())
            case .failure(let error):
                Card { Label(error.localizedDescription, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
            Text("Estimates use your car's limits and charging efficiency. Actual speed may vary with temperature and station load.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showLog, onDismiss: { NotificationCenter.default.post(name: .chargeFormDismissed, object: nil) }) {
            ChargeFormView(draft: makeDraft())
        }
        .onChange(of: store.profile?.preferences) { _ in copied = false }
    }

    private var modeChips: some View {
        ForEach(CalculationMode.allCases) { mode in
            Chip(title: mode.label, selected: prefs.mode == mode) { store.updateProfile { $0.preferences.mode = mode } }
        }
    }

    private func stepCurrent(_ delta: Double) {
        store.updateProfile { $0.preferences.current = min(100, max(0, $0.preferences.current + delta)) }
    }

    private func makeDraft() -> ChargeDraft {
        guard case .success(let result) = store.result else { return ChargeDraft() }
        var draft = ChargeDraft()
        draft.operatorID = prefs.operatorID
        draft.type = prefs.chargerType
        draft.power = prefs.chargerPower
        draft.start = prefs.current
        draft.end = (result.finalPercent * 10).rounded() / 10
        draft.billed = ChargeDraft.round(result.energyToBuy)
        draft.amount = ChargeDraft.round(result.total)
        draft.rate = prefs.rate
        return draft
    }
}

private struct ResultCard: View {
    @Environment(\.colorScheme) private var scheme
    let result: CalculationResult
    let prefs: Preferences
    let op: ChargingOperator?
    @Binding var copied: Bool
    @State private var expanded = false
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("ON THE CHARGER APP", systemImage: "bolt.fill").font(.caption.weight(.bold))
                    Spacer()
                    Text(prefs.chargerType.label).font(.caption.bold()).padding(8).background(.white.opacity(0.15), in: Capsule())
                }
                Text("Enter \(Display.number(result.enterKWh, digits: 0)) kWh")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                if prefs.mode != .target { Text("Reach \(Display.number(result.finalPercent))% charge").font(.title3.weight(.semibold)).monospacedDigit() }
                HStack {
                    Label(Display.money(result.total), systemImage: "indianrupeesign.circle")
                    Spacer()
                    Label("~" + Display.duration(result.hours), systemImage: "clock")
                }.font(.subheadline.weight(.semibold)).monospacedDigit()
                Button {
                    UIPasteboard.general.string = Display.number(result.enterKWh, digits: 0).replacingOccurrences(of: ",", with: "")
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy kWh", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(.plain).background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }.padding(20).foregroundStyle(scheme == .dark ? Color(hex: 0x052e16) : .white)
                .background(LinearGradient(colors: [VoltTheme.accent(scheme), Color(hex: scheme == .dark ? 0x4ade80 : 0x15803d)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            Text("\(Display.money(prefs.rate)) / kWh · \(prefs.gstTreatment.label)").font(.subheadline).foregroundStyle(.secondary)
            if let op {
                Text("\(op.name) · session \(Display.money(op.sessionFee)) · idle \(Display.money(op.idleFee))/min")
                    .font(.caption).foregroundStyle(.secondary)
                if op.sessionFee > 0 || op.idleFee > 0 { Text("Fees are separate from the energy estimate and are included when logging a charge.").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(alignment: .top) {
                stat("Energy to add", result.energy, "battery.75percent")
                Spacer()
                stat("Energy to buy", result.energyToBuy, "bolt.fill")
            }
            DetailRow(title: "Effective power", value: "\(Display.number(result.effectivePower)) kW")
            if result.effectivePower < prefs.chargerPower {
                Label("Your car accepts max \(Display.number(result.effectivePower)) kW \(prefs.chargerType.label)", systemImage: "car.fill").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(result.phases.enumerated()), id: \.offset) { _, phase in
                DetailRow(title: "\(Display.number(phase.from))→\(Display.number(phase.to))%\(phase.tapered ? " · tapered" : "")", value: Display.duration(phase.hours))
            }
            if result.phases.count == 2, let phase = result.phases.last {
                Text("Stopping at 80% saves ~\(Display.duration(phase.hours)).").font(.caption).foregroundStyle(.tint)
            }
            if result.capped {
                Label(prefs.mode == .amount ? "Battery fills to 100%; only \(Display.money(result.total)) of your budget is needed." : "Battery fills to 100% after ~\(Display.duration(result.hours)).", systemImage: "info.circle").font(.subheadline).foregroundStyle(.tint)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 12) {
                    DetailRow(title: "Base price (excl. GST)", value: Display.money(result.base))
                    if prefs.gstTreatment != .none { DetailRow(title: "GST (18%)", value: Display.money(result.gst)) }
                    Divider()
                    DetailRow(title: "Energy total", value: Display.money(result.total))
                }.padding(.vertical, 12)
            } label: { Text("Cost breakdown").font(.subheadline.weight(.semibold)).frame(minHeight: 48) }
        }
    }

    private func stat(_ title: String, _ value: Double, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text("\(Display.number(value)) kWh").font(.title3.bold()).monospacedDigit()
        }
    }
}
