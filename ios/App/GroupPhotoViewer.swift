import SwiftUI
import PhotosUI
import KvittaCore

/// The group picture, whole. The banner crops to fit the card — that is fine for a card — but
/// tapping it lands here, where the entire image is shown and can be replaced or removed.
struct GroupPhotoViewer: View {
    let groupName: String
    let groupId: GroupID
    let photos: GroupPhotoSyncer

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if let data = photos.images.image(for: groupId),
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 12)
                }
            }
            .navigationTitle(GroupBadge.title(of: groupName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Byt bild", systemImage: "photo")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.card, in: .rect(cornerRadius: 22))
                    }

                    Button(role: .destructive) {
                        Task {
                            await photos.stage(nil, for: groupId)
                            dismiss()
                        }
                    } label: {
                        Label("Ta bort", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.negative)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.negative.opacity(0.12), in: .rect(cornerRadius: 22))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .task(id: photoItem) {
                guard let photoItem else { return }
                if let data = try? await photoItem.loadTransferable(type: Data.self),
                   let jpeg = UIImage(data: data)?.downscaled(maxSide: 1200)?
                       .jpegData(compressionQuality: 0.8) {
                    await photos.stage(jpeg, for: groupId)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
