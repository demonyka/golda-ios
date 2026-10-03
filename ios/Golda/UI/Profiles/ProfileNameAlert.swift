import SwiftUI

/// What the name alert is for: a new profile, or a new name for one.
enum ProfileNameRequest: Equatable {
    case create
    case rename(current: String)

    var title: LocalizedStringResource {
        switch self {
        case .create: LocalizedStringResource("New profile", table: "Profiles", comment: "Title of the alert that names a new profile.")
        case .rename: LocalizedStringResource("Rename profile", table: "Profiles", comment: "Title of the alert that renames a profile.")
        }
    }

    var confirmTitle: LocalizedStringResource {
        switch self {
        case .create: LocalizedStringResource("Create", table: "Profiles", comment: "Name alert: creates the profile.")
        case .rename: LocalizedStringResource("Save", table: "Profiles", comment: "Sheets of the profile screen: the main action that saves the change.")
        }
    }

    /// What the field starts with.
    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let current): current
        }
    }
}

/// The alert that names a profile, as the profile menu's: a field, "Отмена", and the confirmation in
/// the system blue (D34), available once the name is not blank. [onConfirm] gets the trimmed name.
private struct ProfileNameAlert: ViewModifier {
    @Binding var request: ProfileNameRequest?
    var onConfirm: (String) -> Void

    @Environment(\.locale) private var locale
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(
                Text(verbatim: request?.title.text(in: locale) ?? ""),
                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } })
            ) {
                TextField(text: $name) {
                    Text("Name", tableName: "Profiles", comment: "Name alert: the profile's name field.")
                }
                .textInputAutocapitalization(.sentences)
                Button(role: .cancel) {} label: {
                    Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
                }
                // The confirm role and the default shortcut make it the alert's preferred button,
                // filled with the system blue (D34).
                Button(role: .confirm) {
                    if let cleaned = ProfileName.cleaned(name) { onConfirm(cleaned) }
                } label: {
                    Text(verbatim: request?.confirmTitle.text(in: locale) ?? "")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ProfileName.cleaned(name) == nil)
            } message: {
                if request == .create {
                    Text("Each profile keeps its own accounts, goals, payments and budget.", tableName: "Profiles", comment: "New profile alert: what a profile is.")
                }
            }
            .onChange(of: request, initial: true) { _, request in
                if let request { name = request.initialName }
            }
    }
}

extension View {
    /// Asks for a profile's name while [request] is set; [onConfirm] gets the trimmed name.
    func profileNameAlert(_ request: Binding<ProfileNameRequest?>, onConfirm: @escaping (String) -> Void) -> some View {
        modifier(ProfileNameAlert(request: request, onConfirm: onConfirm))
    }
}
