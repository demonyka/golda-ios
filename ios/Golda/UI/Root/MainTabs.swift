import GoldaCore
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
    let mic: any MicModel
    @State private var selection = AppTab.home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    TabRoot(tab: tab, data: data, micLayout: micLayout, mic: mic)
                } label: {
                    Label { Text(tab.title) } icon: { Image(systemName: tab.symbol) }
                }
            }
        }
        .modifier(MicAccessoryPlacement(layout: micLayout, mic: mic))
        // Graphite is what is picked: the selected tab, toggles, the cursor (DESIGN.md, "Цвет").
        .tint(Theme.Color.graphite)
    }
}

/// One tab: its own navigation stack with the shared toolbar, its own undo toast, and in the
/// floating layout the mic. The screens replace the placeholders in steps 2a to 2d.
private struct TabRoot: View {
    let tab: AppTab
    let data: AppData
    let micLayout: MicLayout
    let mic: any MicModel

    @Environment(AppModel.self) private var model
    @State private var toast: UndoToast?

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle(Text(tab.title))
                .toolbar { MainToolbar() }
        }
        // Inside the tab view, so the toast floats above the tab bar and the accessory; inside the
        // floating mic's inset, so it floats above that too.
        .undoToast($toast)
        .environment(\.showUndoToast, ShowUndoToastAction { toast = $0 })
        .modifier(MicFloatingPlacement(layout: micLayout, mic: mic))
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home:
            HomeScreen(data: data, today: model.environment.today()) { _ in
                // The operation form arrives in step 2c.
            }
        case .accounts, .goals, .insights:
            TabPlaceholder(tab: tab, profileName: data.profile.name)
        }
    }
}

/// Shows an undo toast over the current tab: `@Environment(\.showUndoToast) var showUndoToast`,
/// then `showUndoToast(UndoToast(...) { ... })`. A new toast replaces the one on screen.
struct ShowUndoToastAction {
    let show: @MainActor (UndoToast) -> Void

    @MainActor func callAsFunction(_ toast: UndoToast) { show(toast) }
}

extension EnvironmentValues {
    /// Nothing happens outside a tab, where no toast host is.
    @Entry var showUndoToast: ShowUndoToastAction = ShowUndoToastAction { _ in }
}

/// The same on every tab: the profile on the left, "+" and settings on the right.
private struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileMenu()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // The operation form arrives in step 2c.
            Button("Add by hand", systemImage: Symbols.add) {}
                .accessibilityIdentifier("add")
            // The settings arrive in step 2e.
            Button("Settings", systemImage: Symbols.settings) {}
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
            .foregroundStyle(Theme.Color.muted)
            .containerRelativeFrame(.vertical)
        }
        .background(Theme.Color.page)
    }
}
