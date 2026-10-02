import SwiftUI

enum VoltTheme {
    static func accent(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x22c55e : 0x16a34a) }
    static func background(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: scheme == .dark ? [Color(hex: 0x0b1220), Color(hex: 0x0f2a3a)] : [Color(hex: 0xe8f4ef), Color(hex: 0xdbe7ff)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x141c2b) : .white }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

enum Display {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_IN")).precision(.fractionLength(digits)))
    }
    static func money(_ value: Double) -> String { "₹" + number(value, digits: 2) }
    static func duration(_ hours: Double) -> String {
        let minutes = (hours * 60).rounded()
        if minutes < 60 { return "\(number(minutes, digits: 0)) min" }
        let remaining = minutes.truncatingRemainder(dividingBy: 60)
        return "\(number(floor(minutes / 60), digits: 0)) hr \(number(remaining, digits: 0)) min"
    }
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(VoltTheme.card(scheme), in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.06), radius: 18, x: 0, y: 8)
    }
}

struct Chip: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle { Text(subtitle).font(.caption) }
            }
            .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
            .foregroundStyle(selected ? (scheme == .dark ? Color(hex: 0x052e16) : .white) : .primary)
            .background(selected ? VoltTheme.accent(scheme) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(scheme == .dark ? Color(hex: 0x052e16) : .white)
            .background(VoltTheme.accent(scheme), in: RoundedRectangle(cornerRadius: 16))
            .opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double
    var suffix = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            HStack {
                TextField(title, value: $value, format: .number.grouping(.never).precision(.fractionLength(0...4)))
                    .keyboardType(.decimalPad).monospacedDigit().accessibilityLabel(title)
                Text(suffix).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).frame(minHeight: 48)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(title, value: $value, format: .number.grouping(.never).precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad).monospacedDigit().padding(.horizontal, 14).frame(minHeight: 48)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }
}

struct Page<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(VoltTheme.background(scheme).ignoresSafeArea())
    }
}
