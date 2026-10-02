import SwiftUI

@main
struct VoltIQApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(colorScheme(for: store.profile?.preferences.appearance ?? .system))
        }
    }

    private func colorScheme(for appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var showUsers = false
    @State private var showLearning = false
    var body: some View {
        Group {
            if store.profile == nil { UserPickerView(isSwitching: false) }
            else {
                TabView {
                    navigation("Calculator") { CalculatorView() }.tabItem { Label("Calculator", systemImage: "bolt.fill") }
                    navigation("History") { HistoryView() }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    navigation("Settings") { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
        }.tint(VoltTheme.accent(scheme))
            .sheet(isPresented: $showUsers) { UserPickerView(isSwitching: true) }
            .alert("Device storage", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                Button("OK", role: .cancel) { store.storageError = nil }
            } message: { Text(store.storageError ?? "") }
            .alert("Learned charging efficiency", isPresented: $showLearning) {
                Button("Use learned value") { if let type = store.learnedPrompt { store.useLearned(type) } }
                Button("Keep my setting", role: .cancel) { store.learnedPrompt = nil }
            } message: { Text(learningMessage) }
            .onReceive(NotificationCenter.default.publisher(for: .chargeFormDismissed)) { _ in showLearning = store.learnedPrompt != nil }
    }

    private var learningMessage: String {
        guard let type = store.learnedPrompt, let profile = store.profile, let learned = LearnedEfficiency.compute(profile.entries, type: type) else { return "" }
        return "From \(learned.count) \(type.label) charges, your real efficiency is \(Display.number(learned.average * 100))%. Use this for future estimates? You can change it in Settings."
    }

    private func navigation<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Label("voltIQ", systemImage: "bolt.fill").font(.headline).foregroundStyle(VoltTheme.accent(scheme))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showUsers = true } label: { Image(systemName: "person.crop.circle").font(.title2).frame(minWidth: 48, minHeight: 48) }
                            .accessibilityLabel("Who's charging? \(store.profile?.name ?? "")")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.frame(minHeight: 48) }
                }
        }
    }
}

extension Notification.Name { static let chargeFormDismissed = Notification.Name("voltIQ.chargeFormDismissed") }
