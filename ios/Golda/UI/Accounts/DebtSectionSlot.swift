import GoldaCore
import SwiftUI

/// Where an account's page shows its debt, between the hero and the operations. The debt's details
/// and the early-repayment calculator (the debts task of step 2b, `UI/Debts`) go here as list
/// sections, for a credit card or a loan (`state.account.isDebt`), as Android's `DebtDetails` tile
/// under the hero. It is handed the account's state and draws nothing until they are wired in.
struct DebtSectionSlot: View {
    let state: AccountState

    var body: some View {
        EmptyView()
    }
}
