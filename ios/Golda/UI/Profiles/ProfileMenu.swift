import SwiftUI

/// The active profile's name with a chevron, in every tab's toolbar. Picking a profile switches the
/// whole app; the menu also creates one and leads to the profiles screen (D23).
struct ProfileMenu: View {
    @Environment(AppModel.self) private var model
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Picker("Profile", selection: activeProfile) {
                ForEach(model.profiles) { profile in
                    Text(verbatim: profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.inline)
            Section {
                Button("New profile", systemImage: "plus") {
                    newName = ""
                    isNaming = true
                }
                .accessibilityIdentifier("profileMenu.new")
                // The profiles screen arrives in step 2e.
                Button("Manage profiles", systemImage: "person.crop.circle") {}
                    .accessibilityIdentifier("profileMenu.manage")
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: name)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("Profile: \(name)"))
        .accessibilityIdentifier("profileMenu")
        .alert("New profile", isPresented: $isNaming) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) {}
            Button("Create", action: create)
                .disabled(trimmedName.isEmpty)
        } message: {
            Text("Each profile keeps its own accounts, goals and budget.")
        }
    }

    private var name: String { model.activeProfile?.name ?? "" }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var activeProfile: Binding<UUID?> {
        Binding(
            get: { model.activeProfileId },
            set: { id in if let id { model.switchProfile(to: id) } }
        )
    }

    private func create() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        Task {
            // A failed write leaves the list as it was, and the menu offers the same again.
            _ = try? await model.createProfile(name: name)
        }
    }
}
