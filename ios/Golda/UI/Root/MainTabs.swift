import SwiftUI

/// The four sections of the app. Each keeps its own navigation; there is no swiping between them (D12).
enum AppTab: Hashable, CaseIterable {
    case home, accounts, goals, insights

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .accounts: "Accounts"
        case .goals: "Goals"
        case .insights: "Insights"
        }
    }

    /// The tab bar fills the selected one by itself.
    var symbol: String {
        switch self {
        case .home: "house"
        case .accounts: "wallet.pass"
        case .goals: "flag"
        case .insights: "chart.pie"
        }
    }
}

/// The tabs of the open profile, with the microphone in the layout under trial (O4).
struct MainTabs: View {
    let data: AppData
    let micLayout: MicLayout
    @State private var selection = AppTab.home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    TabRoot(tab: tab, data: data, micLayout: micLayout)
                } label: {
                    Label { Text(tab.title) } icon: { Image(systemName: tab.symbol) }
                }
            }
        }
        .modifier(MicAccessoryPlacement(layout: micLayout))
    }
}

/// One tab: its own navigation stack with the shared toolbar. The screens replace the placeholder
/// in steps 2a to 2d.
private struct TabRoot: View {
    let tab: AppTab
    let data: AppData
    let micLayout: MicLayout

    var body: some View {
        NavigationStack {
            TabPlaceholder(tab: tab, profileName: data.profile.name)
                .navigationTitle(Text(tab.title))
                .toolbar { MainToolbar() }
        }
        // On the stack, not on the tab view: here the safe area already stops above the tab bar,
        // and the button stays put while screens are pushed.
        .overlay(alignment: .bottomTrailing) {
            if micLayout == .floating {
                FloatingMicButton()
                    .padding(16)
            }
        }
    }
}

/// The same on every tab: the profile on the left, "+" and settings on the right.
private struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileMenu()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // The operation form arrives in step 2c.
            Button("Add by hand", systemImage: "plus") {}
                .accessibilityIdentifier("add")
            // The settings arrive in step 2e.
            Button("Settings", systemImage: "gearshape") {}
                .accessibilityIdentifier("settings")
        }
    }
}

private struct TabPlaceholder: View {
    let tab: AppTab
    let profileName: String

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label { Text(tab.title) } icon: { Image(systemName: tab.symbol) }
            } description: {
                Text("Profile: \(profileName)")
            }
            .containerRelativeFrame(.vertical)
        }
    }
}
