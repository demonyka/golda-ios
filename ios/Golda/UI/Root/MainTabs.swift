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

/// The tabs of the open profile, each with the floating mic. The screens over them (the operation
/// form, settings, profiles) open through the `AppRouter` it puts in the environment, from any tab
/// and over any page pushed on it.
///
/// The tabs set no tint: the accent is the system blue (D34). A tint here reaches every screen,
/// sheet and alert under the tabs; the graphite one made their buttons read as grey, disabled text.
struct MainTabs: View {
    let data: AppData
    let mic: any MicModel
    @State private var selection: AppTab
    /// Accounts in reconcile mode: the Sunday reminder (stage 4) opens the tab this way.
    @State private var isReconciling: Bool
    @State private var router = AppRouter()
    /// One toast for all tabs: the screens over the tabs report through it too, after they close.
    @State private var toast: UndoToast?

    init(data: AppData, mic: any MicModel, tab: AppTab = .home, reconciling: Bool = false) {
        self.data = data
        self.mic = mic
        _selection = State(initialValue: tab)
        _isReconciling = State(initialValue: reconciling)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    TabRoot(tab: tab, data: data, mic: mic, isReconciling: $isReconciling, toast: $toast)
                } label: {
                    Label { Text(tab.title) } icon: { Image(systemName: tab.symbol) }
                }
            }
        }
        // Leaving Accounts ends a reconcile round, as on Android.
        .onChange(of: selection) { _, tab in
            if tab != .accounts { isReconciling = false }
        }
        // The bar stays whole. On iOS 26.2 `.onScrollDown` folds it on the way down but opens it
        // again only back at the very top or on a tap, never on a scroll up: a plain UIKit
        // `UITabBarController` with a table does the same, so it is the system, not this layout.
        // A half-hidden bar that a scroll up does not bring back reads as broken, and the mic
        // above it has no reason to move.
        .tabBarMinimizeBehavior(.never)
        // Over the whole TabView, so a screen opens the same from every tab and over pushed pages.
        .sheet(item: $router.presented) { route in
            RouteDestination(route: route, data: data)
                // A sheet is outside every tab's host; what it reports shows on the tab under it.
                .environment(\.showUndoToast, ShowUndoToastAction { toast = $0 })
        }
        .environment(router)
    }
}

/// One tab: its own navigation stack with the shared toolbar, and on its screen an undo toast and
/// the mic; the account form opens over it. The screens replace the placeholders in steps 2a to 2d.
private struct TabRoot: View {
    let tab: AppTab
    let data: AppData
    let mic: any MicModel
    @Binding var isReconciling: Bool
    @Binding var toast: UndoToast?

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var path = NavigationPath()
    @State private var accountForm: AccountFormRequest?

    /// The account form over the tab: empty from "+ Счёт", or for an account from its page.
    private struct AccountFormRequest: Identifiable {
        let account: Account?
        let id = UUID()
    }

    var body: some View {
        NavigationStack(path: $path) {
            screen
                // Inside the mic's inset, so the toast floats above the mic and the tab bar.
                .undoToast(path.isEmpty ? $toast : .constant(nil))
                .environment(\.showUndoToast, ShowUndoToastAction { toast = $0 })
                // On the screen, not around the stack, so its list ends above the mic (`MicPlacement`).
                .modifier(MicPlacement(mic: mic))
                .navigationTitle(Text(tab.title))
                .toolbar { MainToolbar(router: router) }
        }
        // A page pushed over the screen hides the screen's toast, so over a page it shows here.
        .undoToast(path.isEmpty ? .constant(nil) : $toast)
        .sheet(item: $accountForm) { request in
            AccountFormSheet(
                data: data, editing: request.account,
                onDismiss: { accountForm = nil },
                // Only an account's page edits an account, so the page on top is the deleted one's.
                onDeleted: { if !path.isEmpty { path.removeLast() } }
            )
        }
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home:
            HomeScreen(data: data, today: model.environment.today(), onEdit: edit)
        case .accounts:
            AccountsScreen(
                data: data,
                today: model.environment.today(),
                reconcileMode: isReconciling,
                onAddAccount: { accountForm = AccountFormRequest(account: nil) },
                onEditAccount: { accountForm = AccountFormRequest(account: $0) },
                onEditOperation: edit,
                onAllReconciled: { isReconciling = false }
            )
        case .goals:
            GoalsScreen(data: data)
        case .insights:
            TabPlaceholder(tab: tab, profileName: data.profile.name)
        }
    }

    /// An operation's row, on Home or an account's page, opens the form for it.
    private func edit(_ operation: OperationFull) {
        router.present(.entry(EntryRequest(editing: operation)))
    }
}

/// Shows an undo toast over the current tab's screen: `@Environment(\.showUndoToast) var showUndoToast`,
/// then `showUndoToast(UndoToast(...) { ... })`. A new toast replaces the one on screen.
struct ShowUndoToastAction {
    let show: @MainActor (UndoToast) -> Void

    @MainActor func callAsFunction(_ toast: UndoToast) { show(toast) }
}

extension EnvironmentValues {
    /// Nothing happens where no toast host is above: a tab's screen has one, and a page pushed over
    /// it brings its own, since the screen's toast would show under the page.
    @Entry var showUndoToast: ShowUndoToastAction = ShowUndoToastAction { _ in }
}

/// The same on every tab: the profile on the left, "+" and settings on the right.
private struct MainToolbar: ToolbarContent {
    let router: AppRouter

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileMenu()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Add by hand", systemImage: Symbols.add) {
                router.present(.entry(EntryRequest()))
            }
            .accessibilityIdentifier("add")
            Button("Settings", systemImage: Symbols.settings) {
                router.present(.settings)
            }
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
