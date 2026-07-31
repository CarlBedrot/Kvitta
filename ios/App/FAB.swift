import SwiftUI

/// The floating action button: a perfect burnt-orange circle, soft shadow, the one pop of colour
/// on the screen. It no longer acts directly — tapping it opens `FABMenu`, where every action has
/// a name. A bare plus was read as "add a group" on the first run with a real person; a menu that
/// says "Lägg till utgift" and "Ny grupp" cannot be misread.
struct FAB: View {
    var isOpen: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: .circle)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.spring(duration: 0.3), value: isOpen)
        .accessibilityLabel(isOpen ? "Stäng" : "Lägg till")
    }
}

/// The sheet the FAB opens: a dimmed backdrop and a white card of named actions rising from the
/// bottom, Apple-style. Each row is an icon badge, a title, and one line saying what it does.
struct FABMenu: View {
    struct Action: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let caption: LocalizedStringKey
        let systemImage: String
        let perform: () -> Void
    }

    let actions: [Action]
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)

            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                .padding(.leading, 68)
                        }
                        MenuRow(action: action)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 28))

                Button("Avbryt", action: onDismiss)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.card, in: .rect(cornerRadius: 22))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct MenuRow: View {
    let action: FABMenu.Action

    var body: some View {
        Button(action: action.perform) {
            HStack(spacing: 14) {
                IconBadge(systemImage: action.systemImage, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(action.caption)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
