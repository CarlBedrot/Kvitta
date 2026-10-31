import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// The app shell: Steven's three tabs, Grupper · Notiser · Mer (README §6.1).
///
/// This owns the presentation flows — Ny grupp and Gå med i grupp — so every screen below stays a
/// pure read of the projection. There is no global add: expenses are added from inside a group,
/// and with no group yet the empty Grupper list is the way in.
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

    @State private var selectedTab: Steven.RootTab = .groups
    @State private var showingNewGroup = false
    @State private var showingJoin = false
    /// Held here so creating a group can push straight into it. A new group has nobody in it yet,
    /// so landing back on the list would leave you looking at a row you cannot do anything with.
    @State private var grupperPath = NavigationPath()
    /// Owned here rather than by `ActivityView`, because the badge has to be right on the tab bar
    /// while the feed itself is off screen — which is the only time the badge matters.
    @State private var unread = UnreadStore()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass == .regular }

    /// Unread entries the Notiser feed actually lists. `unread.count` also counts things the feed
    /// never shows — somebody joining by invite, an expense that does not involve you — and a
    /// badge that promises notifications nobody can find reads as a bug.
    private var unreadBadge: Int {
        unread.count(within: FeedEntry.build(from: ledger.state, userId: userId))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(Steven.RootTab.groups.title, systemImage: "person.2", value: Steven.RootTab.groups) {
                grupperTab.modifier(PhoneTabBarHidden(isRegular: isRegular))
            }
            Tab(Steven.RootTab.notifications.title, systemImage: "bell", value: Steven.RootTab.notifications) {
                NavigationStack {
                    ActivityView(ledger: ledger, userId: userId, unread: unread)
                }
                .modifier(PhoneTabBarHidden(isRegular: isRegular))
            }
            .badge(unreadBadge)
            Tab(Steven.RootTab.more.title, systemImage: "ellipsis", value: Steven.RootTab.more) {
                MerView(ledger: ledger, sync: sync, profile: profile, session: session,
                        reminders: reminders, rates: rates, userId: userId)
                    .modifier(PhoneTabBarHidden(isRegular: isRegular))
            }
        }
        // iPad keeps the system sidebar with the same three destinations. The phone draws
        // Steven's white bar itself: the system bar cannot be made to match 01/04/05.
        .modifier(AdaptiveTabStyle(isRegular: isRegular))
        .safeAreaInset(edge: .top, spacing: 0) {
            SyncStatusBanner(status: sync.status) {
                Task { await sync.syncAll() }
            }
            .padding(.horizontal, 20)
            .padding(.top, isRegular ? 20 : 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hidden inside a group, as in Steven (08 has no tab bar).
            if !isRegular && (selectedTab != .groups || grupperPath.isEmpty) {
                Steven.TabBar(selection: $selectedTab, badges: [.notifications: unreadBadge])
            }
        }
        .background(StevenColor.screen.ignoresSafeArea())
        // One accent for the whole app. Without this every control that falls back to the
        // system accent comes out iOS blue.
        .tint(Theme.accent)
        // Set once, read by every avatar of you anywhere below — including inside sheets, which
        // inherit the environment from whatever presented them.
        .environment(\.myAvatarPhoto, profile.avatarData)
        .fullScreenCover(isPresented: Binding(
            get: { !profile.isPaymentProfileComplete }, set: { _ in }
        )) {
            ProfileEditorView(profile: profile, required: true)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(
                ledger: ledger, userId: userId, profile: profile,
                onCreated: { groupId in
                    selectedTab = .groups
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
        // Your saved payment number up to the mutable server profile. The id
        // includes the sign-in state so the first push after signing in is not missed.
        .task(id: "\(profile.swishNumber)|\(session.isSignedIn)") {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await profiles.push(profile)
        }
        #if DEBUG
        // `-StevenRootTab notifications|more`: opens on that tab, so the simulator screenshots
        // that verify the Steven screens can be taken without tapping (#146).
        .onAppear {
            switch UserDefaults.standard.string(forKey: "StevenRootTab") {
            case "notifications": selectedTab = .notifications
            case "more": selectedTab = .more
            default: break
            }
        }
        #endif
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
                     onProfile: { selectedTab = .more })
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
            content
        }
    }
}

/// On the phone the system tab bar gives way to `Steven.TabBar`. It has to be hidden from inside
/// each tab: a `TabView` only listens to its children for its own bar.
private struct PhoneTabBarHidden: ViewModifier {
    let isRegular: Bool

    func body(content: Content) -> some View {
        content.toolbarVisibility(isRegular ? .automatic : .hidden, for: .tabBar)
    }
}
