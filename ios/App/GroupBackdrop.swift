import SwiftUI
import KvittaCore

/// Group photos belong in their explicit photo/header view. All group content shares the
/// editorial canvas so a photo or tint cannot change text contrast behind the expense list.
struct GroupBackdrop: View {
    let tint: Theme.GroupTint
    var photo: UIImage? = nil

    var body: some View { Theme.bg.ignoresSafeArea().accessibilityHidden(true) }
}
