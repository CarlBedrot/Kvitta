import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// The app shell: three tabs over the warm off-white ground, one burnt-orange FAB on Grupper.
///
/// This owns the presentation flows — Ny grupp and Ny utgift — plus the FAB and its action menu,
/// so every screen below stays a pure read of the projection.
struct RootView: View {
    let ledger: LedgerStore
    let userId: UserID
    let sync: SyncEngine
    let profile: UserProfile
    let session: SessionModel
    let invites: InviteModel
    let reminders: ReminderScheduler

    private enum AppTab: Hashable { case grupper, aktivitet, jag }

    @State private var selectedTab: AppTab = .grupper
    @State private var showingNewGroup = false
    @State private var expenseModel: NewExpenseModel?
    @State private var showingActions = false
    /// Held here so creating a group can push straight into it. A new group has nobody in it yet,
    /// so landing back on the list would leave you looking at a row you cannot do anything with.
    @State private var grupperPath = NavigationPath()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Grupper", systemImage: "person.2", value: AppTab.grupper) {
                    grupperTab
                }
                Tab("Aktivitet", systemImage: "arrow.triangle.2.circlepath", value: AppTab.aktivitet) {
                    NavigationStack {
                        ActivityView(ledger: ledger, userId: userId)
                    }
                }
                Tab("Jag", systemImage: "person.crop.circle", value: AppTab.jag) {
                    JagView(ledger: ledger, sync: sync, profile: profile, session: session,
                            invites: invites, reminders: reminders, userId: userId)
                }
            }

            // The FAB's action menu floats above everything, tab bar included — it is a modal
            // moment, and the dim behind it says so.
            if showingActions {
                FABMenu(actions: fabActions) {
                    withAnimation(.spring(duration: 0.3)) { showingActions = false }
                }
            }
        }
        // One accent for the whole app. Without this the selected tab, and every control that
        // falls back to the system accent, comes out iOS blue.
        .tint(Theme.accent)
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
                    // Hidden on the empty state, which carries its own call to action.
                    if !ledger.state.groups.isEmpty {
                        FAB(isOpen: showingActions) {
                            withAnimation(.spring(duration: 0.3)) { showingActions.toggle() }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 80)
                    }
                }
        }
    }

    /// What the plus can mean here, each spelled out. "Registrera betalning" and "Skanna kvitto"
    /// belong to flows that live elsewhere or do not exist yet; a menu row that opens the wrong
    /// screen would be worse than a shorter menu.
    private var fabActions: [FABMenu.Action] {
        [
            FABMenu.Action(
                title: "Lägg till utgift",
                caption: "Dela en ny kostnad med gruppen",
                systemImage: "receipt"
            ) {
                withAnimation(.spring(duration: 0.3)) { showingActions = false }
                startAddExpense()
            },
            FABMenu.Action(
                title: "Ny grupp",
                caption: "Starta en grupp och bjud in med en länk",
                systemImage: "person.badge.plus"
            ) {
                withAnimation(.spring(duration: 0.3)) { showingActions = false }
                showingNewGroup = true
            }
        ]
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
