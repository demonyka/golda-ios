import SwiftUI

/// The active profile's name with a chevron, in every tab's toolbar. Picking a profile switches the
/// whole app; the menu also creates one and leads to the profiles screen (D23).
struct ProfileMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
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
                Button("Manage profiles", systemImage: "person.crop.circle") {
                    router.present(.profiles)
                }
                .accessibilityIdentifier("profileMenu.manage")
            }
        } label: {
            // The name in the text ink and the chevron quieter, the way the toolbar's other glyphs
            // sit: no accent colour on a toolbar control (D34).
            HStack(spacing: Theme.Gap.xs) {
                Text(verbatim: name)
                    .font(.headline)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                Image(systemName: Symbols.profileMenu)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Color.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Gap.xs)
        }
        .accessibilityLabel(Text("Profile: \(name)"))
        .accessibilityHint(Text("Switches the profile the whole app shows"))
        .accessibilityIdentifier("profileMenu")
        .alert("New profile", isPresented: $isNaming) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) {}
            // The confirm role and the default shortcut make it the alert's preferred button, filled
            // with the system blue (D34).
            Button("Create", role: .confirm, action: create)
                .keyboardShortcut(.defaultAction)
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
