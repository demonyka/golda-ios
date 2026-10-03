import GoldaCore
import SwiftUI

/// Home of the open profile: the hero card as the first row, then the operations grouped by day in
/// an inset-grouped list. Tapping an operation hands it to [onEdit] (the form arrives in step 2c).
struct HomeScreen: View {
    let data: AppData
    let today: LocalDate
    var onEdit: (OperationFull) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let content = HomeContent(data: data, today: today)
        List {
            Section {
                HomeHeroView(hero: content.hero)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if content.days.isEmpty {
                Section {
                    Text(verbatim: HomeContent.emptyText.text(in: locale))
                        .font(.body)
                        .foregroundStyle(Theme.Color.muted)
                        .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.l, bottom: Theme.Gap.s, trailing: Theme.Gap.l))
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("home.empty")
                }
            }
            OperationDaySections(days: content.days, rowIdentifier: "home.operation", onSelect: onEdit)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: content.days.map(\.rows))
    }
}

// MARK: - Previews

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            HomeScreen(data: data, today: model.environment.today()) { _ in }
                .navigationTitle(Text(AppTab.home.title))
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            HomeScreen(data: data, today: model.environment.today()) { _ in }
                .navigationTitle(Text(AppTab.home.title))
        }
    }
    .environment(model)
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
    .task { await model.start(command: .samples) }
}
