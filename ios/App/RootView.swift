import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// The app shell: four destinations with a central add-expense action.
///
/// This owns the presentation flows — Ny grupp, Gå med i grupp and Ny utgift — so
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

    fileprivate enum AppTab: Hashable { case overview, grupper, add, stallning, profil }

    @State private var selectedTab: AppTab = .overview
    @State private var previousTab: AppTab = .overview
    @State private var showingNewGroup = false
    @State private var showingJoin = false
    @State private var expenseModel: NewExpenseModel?
    @State private var choosingGroup = false
    private var images: GroupImageStore { photos.images }
    /// What the group chooser decided, applied in its `onDismiss` — presenting the next sheet
    /// while the chooser is still animating away would silently swallow it.
    @State private var chosenGroup: GroupID?
    @State private var chooserWantsNewGroup = false
    @State private var showingActivity = false
    @State private var settlingTransfer: SettlementPresentation?
    @State private var selectedExpense: ExpensePresentation?
    var payees = PayeeDirectory()
    /// Held here so creating a group can push straight into it. A new group has nobody in it yet,
    /// so landing back on the list would leave you looking at a row you cannot do anything with.
    @State private var grupperPath = NavigationPath()
    /// Owned here rather than by `ActivityView`, because the badge has to be right on the tab bar
    /// while the feed itself is off screen — which is the only time the badge matters.
    @State private var unread = UnreadStore()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { rootProxy in
            ZStack {
                TabView(selection: $selectedTab) {
                Tab("Översikt", systemImage: "house.fill", value: AppTab.overview) {
                    NavigationStack {
                        OverviewView(ledger: ledger, userId: userId, profile: profile,
                                     onAddExpense: startAddExpense,
                                     onShowActivity: { showingActivity = true },
                                     onProfile: { selectedTab = .profil },
                                     onOpenActivity: openActivity,
                                     onShowPosition: { selectedTab = .stallning },
                                     onOpenGroup: { groupId in
                                         grupperPath.append(groupId)
                                         selectedTab = .grupper
                                     })
                    }
                }
                Tab("Grupper", systemImage: "person.2", value: AppTab.grupper) {
                    grupperTab
                }
                Tab(value: AppTab.add) {
                    Color.clear
                } label: {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.heroText)
                        }
                        .accessibilityLabel("Lägg till utgift")
                }
                Tab("Ställning", systemImage: "chart.pie", value: AppTab.stallning) {
                    NavigationStack {
                        PositionView(ledger: ledger, userId: userId, profile: profile,
                                     onProfile: { selectedTab = .profil }) { transfer, groupId in
                            settlingTransfer = SettlementPresentation(groupId: groupId, transfer: transfer)
                        }
                    }
                }
                Tab("Profil", systemImage: "person.crop.circle", value: AppTab.profil) {
                    JagView(ledger: ledger, sync: sync, profile: profile, session: session,
                            reminders: reminders, rates: rates, userId: userId)
                }
                }
                .modifier(AdaptiveTabStyle(isRegular: horizontalSizeClass == .regular))
                .toolbar(.hidden, for: .tabBar)

                SyncStatusBanner(status: sync.status) {
                    Task { await sync.syncAll() }
                }
                .padding(.horizontal, 20)
                .padding(.top, horizontalSizeClass == .regular ? 20 : 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if horizontalSizeClass != .regular {
                    PhoneNavigationBar(selection: $selectedTab, onAdd: startAddExpense)
                        .frame(width: max(0, rootProxy.size.width - 24))
                        .padding(.bottom, 4)
                }
            }
        }
        // One accent for the whole app. Without this the selected tab, and every control that
        // falls back to the system accent, comes out iOS blue.
        .tint(Theme.accent)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .add {
                selectedTab = oldValue == .add ? previousTab : oldValue
                startAddExpense()
            } else {
                previousTab = newValue
            }
        }
        // Set once, read by every avatar of you anywhere below — including inside sheets, which
        // inherit the environment from whatever presented them.
        .environment(\.myAvatarPhoto, profile.avatarData)
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(
                ledger: ledger, userId: userId, profile: profile,
                onCreated: { groupId in
                    selectedTab = .grupper
                    grupperPath.append(groupId)
                },
                // One sheet has to be down before the next can come up; the beat is the
                // dismiss animation, not a guess.
                onJoinInstead: {
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        showingJoin = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingJoin) {
            JoinGroupSheet(invites: invites)
        }
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingActivity) {
            NavigationStack {
                ActivityView(ledger: ledger, userId: userId, unread: unread)
            }
        }
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: presentation.groupId,
                          transfer: presentation.transfer, payees: payees)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedExpense) { presentation in
            ExpenseDetailSheet(ledger: ledger, userId: userId, groupId: presentation.groupId,
                               expenseId: presentation.expenseId)
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
                     onProfile: { selectedTab = .profil })
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

    private func openActivity(_ entry: FeedEntry) {
        switch entry.kind {
        case .expense:
            selectedExpense = ExpensePresentation(groupId: entry.groupId, expenseId: ExpenseID(rawValue: entry.id))
        case .payment:
            grupperPath.append(entry.groupId)
            selectedTab = .grupper
        }
    }
}

private struct AdaptiveTabStyle: ViewModifier {
    let isRegular: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRegular {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content.tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

private struct PhoneNavigationBar: View {
    @Binding var selection: RootView.AppTab
    let onAdd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - 10)
            let destinationWidth = max(0, (contentWidth - 48) / 4)

            HStack(spacing: 0) {
                destination(.overview, title: "Översikt", icon: "house", width: destinationWidth)
                destination(.grupper, title: "Grupper", icon: "person.2", width: destinationWidth)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.heroText)
                        .frame(width: 48, height: 48)
                        .background(Theme.hero, in: .circle)
                }
                .frame(width: 48)
                .frame(minWidth: 48, minHeight: 48)
                .accessibilityLabel("Lägg till utgift")
                destination(.stallning, title: "Ställning", icon: "chart.pie", width: destinationWidth)
                destination(.profil, title: "Profil", icon: "person.crop.circle", width: destinationWidth)
            }
            .padding(5)
        }
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .background(Theme.card.opacity(0.97), in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 5)
    }

    private func destination(_ tab: RootView.AppTab, title: String, icon: String, width: CGFloat) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selection == tab ? Theme.accentInk : Theme.ink)
            .frame(width: width)
            .frame(minHeight: 44)
            .padding(.vertical, 7)
            .background(selection == tab ? Theme.accentSubtle : .clear, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

private struct SettlementPresentation: Identifiable {
    let id = UUID()
    let groupId: GroupID
    let transfer: SuggestedTransfer
}

private struct ExpensePresentation: Identifiable {
    let id = UUID()
    let groupId: GroupID
    let expenseId: ExpenseID
}
