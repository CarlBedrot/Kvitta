import SwiftUI
import KvittaCore
import KvittaStorage

/// "Lägg till utgift" from the FAB: first say which group the expense belongs to.
///
/// The FAB used to guess — most recently active group, or bounce to "Ny grupp" when nothing was
/// splittable — and a guess you cannot see is indistinguishable from a redirect. Listing the
/// groups costs one tap and removes the surprise entirely.
struct GroupPickerSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let images: GroupImageStore
    /// Called with the chosen group; the caller opens Ny utgift after this sheet has dismissed.
    let onPick: (GroupID) -> Void
    let onNewGroup: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var groups: [GroupState] { ledger.state.groupsByLastActivity }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 74)
                            }
                            row(for: group)
                        }
                    }
                    .cardSurface(padding: 8)

                    Button {
                        dismiss()
                        onNewGroup()
                    } label: {
                        Label("Ny grupp", systemImage: "person.badge.plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(AmbientBackground())
            .navigationTitle("Vilken grupp?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(for group: GroupState) -> some View {
        // An expense needs someone to split with; a solo group stays visible but says why it
        // cannot be chosen, instead of silently missing from the list.
        let canSplit = group.activeMembers.count >= 2
        return Button {
            dismiss()
            onPick(group.id)
        } label: {
            HStack(spacing: 14) {
                GroupBadge(name: group.name, photo: images.uiImage(for: group.id), size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(GroupBadge.title(of: group.name))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if canSplit {
                        Text("\(group.activeMembers.count) personer")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text("Bara du än — bjud in någon först")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!canSplit)
        .opacity(canSplit ? 1 : 0.5)
    }
}
