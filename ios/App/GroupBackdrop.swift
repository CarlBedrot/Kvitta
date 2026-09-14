import SwiftUI
import KvittaCore

/// The group's own colour as the whole ground of its screens — not a hint at the top, the
/// room you are standing in. A mesh in the group's tint: its deeper voice at the top, the wash
/// through the middle, lightening toward the bottom so the controls down there sit on something
/// calm. Cards stay white on top of it. With a photo, the photo is blurred into the upper half
/// until it is only colour and light.
struct GroupBackdrop: View {
    let tint: Theme.GroupTint
    var photo: UIImage? = nil

    var body: some View {
        let deep = tint.wash.mix(with: tint.foreground, by: 0.45)
        let mid = tint.wash.mix(with: tint.foreground, by: 0.12)
        let light = tint.wash.mix(with: Theme.bg, by: 0.35)
        ZStack(alignment: .top) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45], [0.55, 0.5], [1, 0.4],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    deep, deep, mid,
                    mid, tint.wash, mid,
                    light, light, light,
                ]
            )
            if let photo {
                GeometryReader { geo in
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height * 0.55)
                        .clipped()
                        .blur(radius: 60, opaque: false)
                        .opacity(0.7)
                        .mask(
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                        )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
