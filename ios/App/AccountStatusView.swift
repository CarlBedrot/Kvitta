import SwiftUI
import KvittaStorage
import KvittaSync

/// Mer → Konto (README §4.4 "Offline/sync-status"): sign-in state and anything the server
/// refused. Signing in is optional (CLAUDE.md, Auth) — the app without an account is the offline
/// app, and this screen never implies otherwise.
struct AccountStatusView: View {
    let ledger: LedgerStore
    let session: SessionModel
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Konto", leading: .back { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: StevenMetric.gutter) {
                    Steven.Card {
                        signInRow
                        if let failure = session.failure {
                            // Not `StevenColor.owe`: that coral is deliberately low-contrast
                            // (README §2.1, ~1.5:1 on white) because direction is always also
                            // carried by a word and a sign. An error message has neither, so it
                            // needs a colour that is readable on its own.
                            Text(failure)
                                .stevenFont(.footnote)
                                .foregroundStyle(Theme.negative)
                        }
                    }
                    Text("Du behöver inget konto för att använda Slice. Ett konto gör bara att dina utgifter finns kvar om telefonen försvinner.")
                        .stevenFont(.footnote)
                        .foregroundStyle(StevenColor.muted)

                    if !ledger.rejectedPushes.isEmpty {
                        NavigationLink {
                            RejectedPushList(ledger: ledger)
                        } label: {
                            Steven.ListRow(icon: "exclamationmark.triangle", title: "Kunde inte sparas hos servern",
                                           trailing: .value("\(ledger.rejectedPushes.count)"))
                        }
                        .buttonStyle(Steven.RowButtonStyle())
                    }
                }
                .padding(StevenMetric.gutter)
            }
        }
        .background(StevenColor.screen)
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var signInRow: some View {
        if session.isSignedIn {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(StevenColor.accent)
                Text("Inloggad").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
            }
        } else {
            Button {
                Task { await session.signIn(displayName: profile.displayName) }
            } label: {
                HStack(spacing: 12) {
                    Text("Logga in").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.accent)
                    if session.isWorking { ProgressView() }
                }
            }
            .buttonStyle(.plain)
            .disabled(session.isWorking)
        }
    }
}
