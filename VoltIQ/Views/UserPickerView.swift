import SwiftUI

struct UserPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let isSwitching: Bool
    @State private var name = ""
    @State private var deleting: UserProfile?

    var body: some View {
        NavigationStack {
            Page {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "bolt.fill").font(.system(size: 44)).foregroundStyle(VoltTheme.accent(scheme))
                    Text("Who's charging?").font(.largeTitle.bold())
                    Text("One device, your own settings and history. No account or connection needed.").foregroundStyle(.secondary)
                }.padding(.vertical, 20)
                if !store.state.users.isEmpty {
                    Card {
                        Text("On this device").font(.headline)
                        ForEach(store.state.users) { user in
                            HStack {
                                Button { store.chooseUser(user.id); if isSwitching { dismiss() } } label: {
                                    HStack { Image(systemName: "person.circle.fill"); Text(user.name); Spacer(); Text("\(user.entries.count) charges").font(.caption).foregroundStyle(.secondary) }
                                        .frame(minHeight: 48).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button(role: .destructive) { deleting = user } label: { Image(systemName: "trash").frame(width: 48, height: 48) }.accessibilityLabel("Delete \(user.name)")
                            }
                        }
                    }
                }
                Card {
                    Text("New driver").font(.headline)
                    TextField("Your name", text: $name).textContentType(.nickname).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 14).frame(minHeight: 48).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit { addUser() }
                    Button("Let's charge", action: addUser).buttonStyle(PrimaryButton()).disabled(UserProfile.normalize(name).isEmpty)
                }
            }.toolbar {
                if isSwitching { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.frame(minHeight: 48) } }
            }
        }.tint(VoltTheme.accent(scheme))
            .alert("Delete this driver?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete driver", role: .destructive) { if let deleting { store.deleteUser(deleting.id) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("\(deleting?.name ?? "")'s settings, history and receipt photos will be deleted from this device.") }
    }

    private func addUser() {
        store.addUser(name)
        if isSwitching, store.storageError == nil { dismiss() }
    }
}
