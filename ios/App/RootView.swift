import SwiftUI
import KvittaCore
import KvittaStorage

/// The app shell: a floating glass capsule tab bar (the iOS 26 default) over opaque content.
/// Grupper is the built screen this round; Aktivitet and Jag are placeholders for later rounds.
///
/// This owns the two presentation flows — Ny grupp and Ny utgift — and the clay FAB, so the
/// glass on the Grupper screen stays at exactly two elements (tab bar + FAB).
struct RootView: View {
    let ledger: LedgerStore
    let userId: UserID

    @State private var showingNewGroup = false
    @State private var expenseModel: NewExpenseModel?

    var body: some View {
        TabView {
            Tab("Grupper", systemImage: "person.2") {
                grupperTab
            }
            Tab("Aktivitet", systemImage: "arrow.triangle.2.circlepath") {
                ComingSoonView(title: "Aktivitet", systemImage: "arrow.triangle.2.circlepath")
            }
            Tab("Jag", systemImage: "person.crop.circle") {
                JagView(ledger: ledger)
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

/// Placeholder for a tab whose screen arrives in a later round.
private struct ComingSoonView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("Kommer snart.")
        }
        .background(AmbientBackground())
    }
}

/// Jag: profile and settings land here later. For now it keeps the developer affordances the old
/// diagnostics screen had — rebuild the projection from the log, and insert the worked-example
/// seed data — plus the sync counters.
private struct JagView: View {
    let ledger: LedgerStore
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
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

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }
}
