import Foundation
import KvittaCore

/// What a photo fetch came back with.
public enum GroupPhotoFetch: Sendable, Equatable {
    /// The server's photo matches the etag you sent — nothing travelled.
    case unchanged
    /// The group has no photo (any more).
    case none
    /// A photo, with the etag to send next time.
    case photo(Data, etag: String)
}

/// The group's shared picture on the server: any member may set or clear it, only members are
/// served it.
///
/// The same "mutable server field, never an event" shape as `ProfileTransport`, for the same
/// reason: a photo in the immutable log would reach every member forever with no way to take it
/// back. Last write wins, like the group's name.
public protocol GroupPhotoTransport: Sendable {
    func setGroupPhoto(_ jpeg: Data, in groupId: GroupID) async throws
    func clearGroupPhoto(in groupId: GroupID) async throws
    /// Pass the etag from the last `.photo` you kept; a match costs no body.
    func groupPhoto(in groupId: GroupID, matching etag: String?) async throws -> GroupPhotoFetch
}

extension HTTPSyncTransport: GroupPhotoTransport {
    public func setGroupPhoto(_ jpeg: Data, in groupId: GroupID) async throws {
        var request = makeAuthorisableRequest(path: photoPath(groupId))
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        _ = try await performAuthorised(request)
    }

    public func clearGroupPhoto(in groupId: GroupID) async throws {
        var request = makeAuthorisableRequest(path: photoPath(groupId))
        request.httpMethod = "DELETE"
        _ = try await performAuthorised(request)
    }

    public func groupPhoto(
        in groupId: GroupID,
        matching etag: String?
    ) async throws -> GroupPhotoFetch {
        var request = makeAuthorisableRequest(path: photoPath(groupId))
        // The etag comparison is ours, not URLCache's — letting the cache answer would turn the
        // server's 304 into a stale 200 and the "did it change" question could never be asked.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (body, headers) = try await performAuthorisedReadingHeaders(request)
            guard let fetchedTag = headers["Etag"] ?? headers["ETag"] else {
                throw SyncError.malformedResponse("Photo response carried no ETag.")
            }
            return .photo(body, etag: fetchedTag)
        } catch SyncError.server(304, _) {
            return .unchanged
        } catch SyncError.server(404, _) {
            return .none
        }
    }

    private func photoPath(_ groupId: GroupID) -> String {
        "api/v1/groups/\(groupId.rawValue.uuidString.lowercased())/photo"
    }
}
