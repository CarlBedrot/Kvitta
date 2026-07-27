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
                JagView(ledger: ledger, sync: sync)
            }
        }
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

/// Jag: profile and settings land here later. For now it keeps the developer affordances the old
/// diagnostics screen had — rebuild the projection from the log, and insert the worked-example
/// seed data — plus the sync counters.
private struct JagView: View {
    let ledger: LedgerStore
    let sync: SyncEngine
    @State private var failure: String?
    @State private var syncEnabled = UserDefaults.standard.bool(forKey: SyncSettings.defaultsKey)

    var body: some View {
        NavigationStack {
            Form {
                Section("Synk") {
                    Toggle("Synka med servern", isOn: $syncEnabled)
                        .onChange(of: syncEnabled) { _, enabled in
                            SyncSettings.setEnabled(enabled)
                            guard enabled else { return }
                            Task { await sync.syncAll() }
                        }
                    LabeledContent("Status", value: statusText)
                    if !ledger.rejectedPushes.isEmpty {
                        // Design doc §7: rejected events are surfaced, never dropped. The
                        // per-row dashed-cloud badge is the in-Xcode agent's job; this is the
                        // state it reads.
                        LabeledContent("Kunde inte synkas", value: "\(ledger.rejectedPushes.count)")
                            .foregroundStyle(Theme.clay)
                    }
                    Button("Synka nu", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sync.syncAll() }
                    }
                    .disabled(!syncEnabled)
                }
                Section("Diagnostik") {
                    LabeledContent("Väntar på push", value: "\((try? ledger.pendingPushCount()) ?? -1)")
                    LabeledContent("Överhoppade händelser", value: "\(ledger.state.skipped.count)")
                    LabeledContent("Olästa rader", value: "\(ledger.rejected.count)")
                }
                Section("Utvecklarverktyg") {
                    Button("Bygg om projektioner från loggen", systemImage: "arrow.clockwise") {
                        perform { try ledger.rebuild() }
                    }
                    Button("Lägg till testdata", systemImage: "plus") {
                        perform { try SeedData.insert(into: ledger) }
                    }
                }
                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Jag")
        }
    }

    private var statusText: String {
        switch sync.status {
        case .disabled: return "Av"
        case .idle: return "Klar"
        case .syncing: return "Synkar…"
        case .offline: return "Offline"          // normal, and not worth alarming anyone about
        case .blocked(let message): return message
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }
}
