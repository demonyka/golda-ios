import GoldaCore
import SwiftUI

/// The five account types as tiles in a row, each its symbol over its short name. The picked one
/// turns graphite and rounds into a pill, as every pick does in Golda. At the accessibility sizes
/// the names no longer fit five abreast, so the tiles stack into full-width rows.
struct AccountTypeTiles: View {
    @Binding var selection: AccountType

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Gap.s) {
                    ForEach(AccountType.allCases, id: \.self) { tile($0, wide: true) }
                }
            } else {
                HStack(spacing: Theme.Gap.s) {
                    ForEach(AccountType.allCases, id: \.self) { tile($0, wide: false) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tile(_ type: AccountType, wide: Bool) -> some View {
        let picked = type == selection
        let title = AccountFormModel.typeTitle(type).text(in: locale)
        return Button {
            selection = type
        } label: {
            Group {
                if wide {
                    HStack(spacing: Theme.Gap.m) {
                        Image(systemName: Symbols.accountType(type))
                        Text(verbatim: title)
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.horizontal, Theme.Gap.m)
                    .padding(.vertical, Theme.Gap.s)
                } else {
                    VStack(spacing: Theme.Gap.xs) {
                        Image(systemName: Symbols.accountType(type))
                            .font(.title3)
                        Text(verbatim: title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(picked ? Theme.Color.onGraphite : Theme.Color.text)
            // 32 is half the height: the picked tile becomes a pill.
            .background(
                picked ? Theme.Color.graphite : Theme.Color.soft,
                in: RoundedRectangle(cornerRadius: picked ? 32 : 20, style: .continuous)
            )
            .contentShape(.rect)
        }
        // Plain, so each tile in the form's row takes its own taps instead of the row taking them all.
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy, value: picked)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("accountForm.type.\(type.rawValue.lowercased())")
    }
}
