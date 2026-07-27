import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// The app shell: a floating glass capsule tab bar (the iOS 26 default) over opaque content.
/// Grupper is the built screen this round; Aktivitet and Jag are placeholders for later rounds.
///
/// This owns the two presentation flows — Ny grupp and Ny utgift — and the clay FAB, so the
/// glass on the Grupper screen stays at exactly two elements (tab bar + FAB).
struct RootView: View {
    let ledger: LedgerStore
    let userId: UserID
    let sync: SyncEngine
    let profile: UserProfile
    let session: SessionModel

    @State private var showingNewGroup = false
    @State private var expenseModel: NewExpenseModel?

    var body: some View {
        TabView {
            Tab("Grupper", systemImage: "person.2") {
                grupperTab
            }
            Tab("Aktivitet", systemImage: "arrow.triangle.2.circlepath") {
                NavigationStack {
                    ActivityView(ledger: ledger, userId: userId)
                }
            }
            Tab("Jag", systemImage: "person.crop.circle") {
                JagView(ledger: ledger, sync: sync, profile: profile, session: session)
            }
        }
        // One accent for the whole app. Without this the selected tab, and every control that
        // falls back to the system accent, comes out iOS blue in a cream-and-clay palette.
        .tint(Theme.clayBright)
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(ledger: ledger, userId: userId)
        }
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
    }

    private var grupperTab: some View {
        NavigationStack {
            HomeView(ledger: ledger, userId: userId, onNewGroup: { showingNewGroup = true })
                .overlay(alignment: .bottomTrailing) {
                    if !ledger.state.groups.isEmpty {
                        FAB(action: startAddExpense)
                            .padding(.trailing, 20)
                            .padding(.bottom, 80)
                    }
                }
        }
    }

    /// Opens Ny utgift on the most recently active group that has someone to split with. With no
    /// such group yet, routes to group creation instead — adding an expense is never a dead end.
    private func startAddExpense() {
        if let groupId = ledger.state.groupsByLastActivity.first(where: { $0.activeMembers.count >= 2 })?.id {
            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
        } else {
            showingNewGroup = true
        }
    }
}
