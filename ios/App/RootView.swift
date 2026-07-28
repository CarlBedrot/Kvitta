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
    let invites: InviteModel
    let reminders: ReminderScheduler

    @State private var showingNewGroup = false
    @State private var expenseModel: NewExpenseModel?
    /// Held here so creating a group can push straight into it. A new group has nobody in it yet,
    /// so landing back on the list would leave you looking at a row you cannot do anything with.
    @State private var grupperPath = NavigationPath()

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
                JagView(ledger: ledger, sync: sync, profile: profile, session: session,
                        invites: invites, reminders: reminders, userId: userId)
            }
        }
        // One accent for the whole app. Without this the selected tab, and every control that
        // falls back to the system accent, comes out iOS blue in a cream-and-clay palette.
        .tint(Theme.clayBright)
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(ledger: ledger, userId: userId, profile: profile) { groupId in
                grupperPath.append(groupId)
            }
        }
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
    }

    private var grupperTab: some View {
        NavigationStack(path: $grupperPath) {
            HomeView(ledger: ledger, userId: userId, invites: invites, profile: profile,
                     onNewGroup: { showingNewGroup = true })
                .overlay(alignment: .bottomTrailing) {
                    // Only when there is a group with someone to split with. A lone group offers
                    // its invite link instead, on the group screen itself.
                    if splittableGroupId != nil {
                        FAB(action: startAddExpense)
                            .padding(.trailing, 20)
                            .padding(.bottom, 80)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingNewGroup = true }) {
                            // A person-with-a-plus, not a bare plus. Two plus signs on one screen
                            // is the confusion this is fixing, not a style it should copy.
                            Label("Ny grupp", systemImage: "person.badge.plus")
                        }
                    }
                }
        }
    }

    /// The most recently active group you can actually split in.
    private var splittableGroupId: GroupID? {
        ledger.state.groupsByLastActivity.first { $0.activeMembers.count >= 2 }?.id
    }

    /// Opens Ny utgift on the most recently active group that has someone to split with. With no
    /// such group yet, routes to group creation instead — adding an expense is never a dead end.
    private func startAddExpense() {
        if let groupId = splittableGroupId {
            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
        } else {
            showingNewGroup = true
        }
    }
}
