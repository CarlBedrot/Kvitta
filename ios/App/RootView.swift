import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// The app shell: three tabs over the warm off-white ground, one accent-coloured FAB on Grupper.
///
/// This owns the presentation flows — Ny grupp, Gå med i grupp and Ny utgift — plus the FAB, so
/// every screen below stays a pure read of the projection.
struct RootView: View {
    let ledger: LedgerStore
    let userId: UserID
    let sync: SyncEngine
    let profile: UserProfile
    let session: SessionModel
    let invites: InviteModel
    let reminders: ReminderScheduler
    let rates: RateStore
    let profiles: ProfileSyncer
    let photos: GroupPhotoSyncer

    private enum AppTab: Hashable { case grupper, aktivitet, jag }

    @State private var selectedTab: AppTab = .grupper
    @State private var showingNewGroup = false
    @State private var showingJoin = false
    @State private var expenseModel: NewExpenseModel?
    @State private var choosingGroup = false
    private var images: GroupImageStore { photos.images }
    /// What the group chooser decided, applied in its `onDismiss` — presenting the next sheet
    /// while the chooser is still animating away would silently swallow it.
    @State private var chosenGroup: GroupID?
    @State private var chooserWantsNewGroup = false
    /// Held here so creating a group can push straight into it. A new group has nobody in it yet,
    /// so landing back on the list would leave you looking at a row you cannot do anything with.
    @State private var grupperPath = NavigationPath()
    /// Owned here rather than by `ActivityView`, because the badge has to be right on the tab bar
    /// while the feed itself is off screen — which is the only time the badge matters.
    @State private var unread = UnreadStore()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Grupper", systemImage: "person.2", value: AppTab.grupper) {
                    grupperTab
                }
                Tab("Aktivitet", systemImage: "arrow.triangle.2.circlepath", value: AppTab.aktivitet) {
                    NavigationStack {
                        ActivityView(ledger: ledger, userId: userId, unread: unread)
                    }
                }
                .badge(unread.count)
                Tab("Jag", systemImage: "person.crop.circle", value: AppTab.jag) {
                    JagView(ledger: ledger, sync: sync, profile: profile, session: session,
                            reminders: reminders, rates: rates, userId: userId)
                }
            }
        }
        // One accent for the whole app. Without this the selected tab, and every control that
        // falls back to the system accent, comes out iOS blue.
        .tint(Theme.accent)
        // Set once, read by every avatar of you anywhere below — including inside sheets, which
        // inherit the environment from whatever presented them.
        .environment(\.myAvatarPhoto, profile.avatarData)
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(ledger: ledger, userId: userId, profile: profile) { groupId in
                grupperPath.append(groupId)
            }
        }
        .sheet(isPresented: $showingJoin) {
            JoinGroupSheet(invites: invites)
        }
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $choosingGroup, onDismiss: applyChooserChoice) {
            GroupPickerSheet(
                ledger: ledger,
                userId: userId,
                images: images,
                onPick: { chosenGroup = $0 },
                onNewGroup: { chooserWantsNewGroup = true }
            )
        }
        // Your Swish number up to your server profile, debounced past the keystrokes. The id
        // includes the sign-in state so the first push after signing in is not missed.
        .task(id: "\(profile.swishNumber)|\(session.isSignedIn)") {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await profiles.push(profile)
        }
        // Keyed on the log's size so a pull that brings somebody else's expenses in updates the
        // badge without the feed being open — which is the only situation where a badge is of any
        // use at all.
        .task(id: ledger.state.appliedEventIds.count) {
            unread.refresh(from: ledger)
        }
    }

    private var grupperTab: some View {
        NavigationStack(path: $grupperPath) {
            HomeView(ledger: ledger, userId: userId, invites: invites, profile: profile,
                     photos: photos, rates: rates, profiles: profiles,
                     onNewGroup: { showingNewGroup = true },
                     onJoin: { showingJoin = true })
                .overlay(alignment: .bottomTrailing) {
                    // Hidden on the empty state, which carries its own call to action.
                    if !ledger.state.groups.isEmpty {
                        FAB(action: startAddExpense)
                            .padding(.trailing, 20)
                            .padding(.bottom, 80)
                    }
                }
        }
    }


    /// Opens Ny utgift. One group with someone to split with goes straight in; anything else —
    /// several groups, or only solo ones — opens the chooser, where the situation is visible.
    /// The old behaviour guessed the most recent group or bounced to "Ny grupp", both of which
    /// read as being redirected somewhere you did not ask to go.
    private func startAddExpense() {
        let groups = ledger.state.groupsByLastActivity
        if groups.isEmpty {
            showingNewGroup = true
        } else if groups.count == 1, let only = groups.first, only.activeMembers.count >= 2 {
            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: only.id)
        } else {
            choosingGroup = true
        }
    }

    /// Runs when the group chooser has fully left the screen; see `chosenGroup`.
    private func applyChooserChoice() {
        if let groupId = chosenGroup {
            chosenGroup = nil
            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
        } else if chooserWantsNewGroup {
            chooserWantsNewGroup = false
            showingNewGroup = true
        }
    }
}
