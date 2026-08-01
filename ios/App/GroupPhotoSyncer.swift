import CryptoKit
import Foundation
import KvittaCore
import KvittaSync
import UIKit

/// Keeps the group picture shared: your pick goes up, co-members' picks come down.
///
/// The server side of `GroupImageStore` — the same "mutable server field, never an event" shape
/// as `ProfileSyncer`, because a photo in the immutable log could never be taken back. Last write
/// wins, like the group's name. Failure is silence: without a server the store simply stays what
/// this device last saw, which is the offline app working as designed.
@MainActor
@Observable
final class GroupPhotoSyncer {
    /// The one store every screen reads. Owned here so the pair cannot drift apart.
    let images: GroupImageStore

    private let transport: any GroupPhotoTransport
    private let session: SessionModel

    init(
        transport: any GroupPhotoTransport,
        session: SessionModel,
        images: GroupImageStore = GroupImageStore()
    ) {
        self.transport = transport
        self.session = session
        self.images = images
    }

    /// The user picked a photo (or removed one, `nil`): shown at once, uploaded when possible.
    func stage(_ jpeg: Data?, for groupId: GroupID) async {
        images.set(jpeg, for: groupId)
        images.setDirty(true, for: groupId)
        await push(groupId)
    }

    /// Uploads a pending local pick. A miss keeps the dirty flag, so the next open retries.
    func push(_ groupId: GroupID) async {
        guard session.isSignedIn, images.isDirty(groupId) else { return }

        if let data = images.image(for: groupId) {
            // A staged photo that outgrew the server's cap (an early build rendered at 3× and
            // stored ~2 MB) is re-encoded instead of staying dirty and retrying forever.
            let payload = Self.fitForUpload(data)
            guard (try? await transport.setGroupPhoto(payload, in: groupId)) != nil else { return }
            if payload != data {
                images.set(payload, for: groupId)
            }
            // The server's tag is content-addressed (SHA-256), so we already know it: the next
            // refresh can 304 without ever re-downloading what we just sent.
            images.setEtag(Self.etag(of: payload), for: groupId)
        } else {
            guard (try? await transport.clearGroupPhoto(in: groupId)) != nil else { return }
            images.setEtag(nil, for: groupId)
        }
        images.setDirty(false, for: groupId)
    }

    /// Brings this device's copy in line with the group's — called when a group is opened.
    func refresh(_ groupId: GroupID) async {
        guard session.isSignedIn else { return }

        // A pending local pick outranks whatever the server has: it is the newest intent we know.
        if images.isDirty(groupId) {
            await push(groupId)
            return
        }

        let current = images.etag(for: groupId)
        guard let fetch = try? await transport.groupPhoto(in: groupId, matching: current) else {
            return
        }

        switch fetch {
        case .unchanged:
            break
        case .none:
            if images.image(for: groupId) != nil && current == nil {
                // A photo picked before photos synced (or while signed out): the server has
                // nothing, we have something — seed it up rather than throw it away.
                images.setDirty(true, for: groupId)
                await push(groupId)
            } else {
                // The photo came from the server and someone took it back. Taking it back is the
                // point of this being a server field, so honour it here too.
                images.set(nil, for: groupId)
                images.setEtag(nil, for: groupId)
            }
        case .photo(let data, let etag):
            images.set(data, for: groupId)
            images.setEtag(etag, for: groupId)
        }
    }

    /// Mirrors the server's `ETagFor`: quoted lowercase SHA-256 hex of the bytes.
    static func etag(of data: Data) -> String {
        "\"" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "\""
    }

    /// The server caps a photo at 1 MB. Anything bigger gets one more pass through the
    /// downscaler; if that somehow fails, the original goes up and the server's answer stands.
    private static let maxUploadBytes = 1_000_000

    static func fitForUpload(_ data: Data) -> Data {
        guard data.count > maxUploadBytes else { return data }
        guard let smaller = UIImage(data: data)?
            .downscaled(maxSide: 1200)?
            .jpegData(compressionQuality: 0.7),
            smaller.count < data.count else { return data }
        return smaller
    }
}
