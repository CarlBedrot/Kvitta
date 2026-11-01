import SwiftUI

/// Joining a group from a pasted invite, for when the link itself did not survive the trip.
/// Steven-styled per README §3.4: `NavTitleBar` "GÅ MED", the code field, and the "Gå med" button
/// below it — the same shape and error handling as before, in Steven's components.
///
/// Tapping the link is the normal path and needs no UI at all. This exists because links get
/// mangled — forwarded through chat apps, screenshotted, read out loud — and a group you cannot
/// join because a URL lost its scheme is a bad afternoon. It takes the bare token too. It sits
/// under the Grupper title next to "Ny grupp", because that is where somebody holding an invite
/// goes looking; it used to be a section on Jag, where nobody found it.
struct JoinGroupSheet: View {
    let invites: InviteModel

    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""

    private var canJoin: Bool { !inviteCode.isEmpty && !invites.isWorking }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Gå med", leading: .close({ dismiss() }))
            ScrollView {
                VStack(spacing: StevenMetric.cardGap) {
                    Steven.Card(padding: 0) {
                        TextField("Klistra in inbjudningskod", text: $inviteCode)
                            .stevenFont(.rowTitle)
                            .foregroundStyle(StevenColor.ink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, StevenMetric.gutter)
                            .frame(minHeight: StevenMetric.rowHeight)
                    }

                    switch invites.outcome {
                    case .failed(let reason):
                        errorNotice(reason)
                    case .joined, nil:
                        EmptyView()
                    }
                }
                .padding(StevenMetric.gutter)
            }
            Button {
                join()
            } label: {
                if invites.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Gå med")
                }
            }
            .buttonStyle(Steven.FilledButtonStyle())
            .disabled(!canJoin)
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 12)
        }
        .background(StevenColor.screen)
        // A stale "failed" from an earlier attempt would greet the next one.
        .onAppear { invites.clear() }
    }

    private func errorNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(StevenColor.badge)
            Text(verbatim: text)
                .stevenFont(.footnote)
                .foregroundStyle(StevenColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StevenMetric.cardPadding)
        .stevenCardBackground()
        .accessibilityElement(children: .combine)
    }

    private func join() {
        Task {
            await invites.accept(rawCode: inviteCode)
            // The group is in the ledger now and shows up on Grupper behind this sheet — the sheet
            // has nothing left to say.
            if case .joined = invites.outcome { dismiss() }
        }
    }
}
