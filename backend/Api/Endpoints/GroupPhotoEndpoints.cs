using System.Security.Cryptography;
using Kvitta.Api.Auth;
using Kvitta.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Endpoints;

/// <summary>
/// The group's shared picture: any member may set or clear it, only members are served it.
/// </summary>
/// <remarks>
/// A mutable column and not an event, for the same reason a Swish number is not one: a photo in
/// the immutable log would reach every member forever with no way to take it back, and at JPEG
/// sizes it would bloat a log that replays on every launch. Last write wins — the same rule the
/// group's name effectively has, and a friend group does not need more.
/// </remarks>
public static class GroupPhotoEndpoints
{
    /// <summary>
    /// A 1200-point square at JPEG 0.8 is ~300 KB; double that and round up. Anything larger is a
    /// client that skipped its own downscaling, not a bigger photo.
    /// </summary>
    private const int MaxPhotoBytes = 1024 * 1024;

    public static void MapGroupPhotoEndpoints(this IEndpointRouteBuilder routes)
    {
        routes.MapPut("/api/v1/groups/{groupId:guid}/photo", SetAsync);
        routes.MapGet("/api/v1/groups/{groupId:guid}/photo", GetAsync);
        routes.MapDelete("/api/v1/groups/{groupId:guid}/photo", ClearAsync);
    }

    private static async Task<IResult> SetAsync(
        Guid groupId,
        HttpContext http,
        KvittaDbContext db,
        CancellationToken cancellationToken)
    {
        var membership = await AuthoriseAsync(http, db, groupId, cancellationToken);
        if (membership.Failure is { } failure)
        {
            return failure;
        }

        if (http.Request.ContentLength is > MaxPhotoBytes)
        {
            return Results.Problem(
                title: "Photo too large",
                detail: $"A group photo may be at most {MaxPhotoBytes / 1024} kB.",
                statusCode: StatusCodes.Status413PayloadTooLarge);
        }

        // Read with a hard cap regardless of the declared length — Content-Length is a claim.
        using var buffer = new MemoryStream();
        await http.Request.Body.CopyToAsync(buffer, cancellationToken);
        if (buffer.Length > MaxPhotoBytes)
        {
            return Results.Problem(
                title: "Photo too large",
                detail: $"A group photo may be at most {MaxPhotoBytes / 1024} kB.",
                statusCode: StatusCodes.Status413PayloadTooLarge);
        }

        var bytes = buffer.ToArray();
        if (bytes.Length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8)
        {
            // The JPEG SOI marker. The client always re-encodes to JPEG before uploading, so
            // anything else is a bug or mischief — refuse rather than serve it to the group.
            return Results.Problem(
                title: "Not a JPEG",
                detail: "Group photos are JPEG bytes.",
                statusCode: StatusCodes.Status422UnprocessableEntity);
        }

        var group = await db.Groups.SingleAsync(g => g.Id == groupId, cancellationToken);
        group.PhotoJpeg = bytes;
        await db.SaveChangesAsync(cancellationToken);

        http.Response.Headers.ETag = ETagFor(bytes);
        return Results.NoContent();
    }

    private static async Task<IResult> GetAsync(
        Guid groupId,
        HttpContext http,
        KvittaDbContext db,
        CancellationToken cancellationToken)
    {
        var membership = await AuthoriseAsync(http, db, groupId, cancellationToken);
        if (membership.Failure is { } failure)
        {
            return failure;
        }

        var photo = await db.Groups
            .Where(g => g.Id == groupId)
            .Select(g => g.PhotoJpeg)
            .SingleOrDefaultAsync(cancellationToken);

        if (photo is null)
        {
            return Results.Problem(
                title: "No photo",
                detail: "This group has no picture.",
                statusCode: StatusCodes.Status404NotFound);
        }

        var etag = ETagFor(photo);
        if (http.Request.Headers.IfNoneMatch.Contains(etag))
        {
            // The common case after the first fetch: the ~300 kB body stays home.
            http.Response.Headers.ETag = etag;
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        http.Response.Headers.ETag = etag;
        return Results.Bytes(photo, contentType: "image/jpeg");
    }

    private static async Task<IResult> ClearAsync(
        Guid groupId,
        HttpContext http,
        KvittaDbContext db,
        CancellationToken cancellationToken)
    {
        var membership = await AuthoriseAsync(http, db, groupId, cancellationToken);
        if (membership.Failure is { } failure)
        {
            return failure;
        }

        var group = await db.Groups.SingleAsync(g => g.Id == groupId, cancellationToken);
        group.PhotoJpeg = null;
        await db.SaveChangesAsync(cancellationToken);
        return Results.NoContent();
    }

    /// <summary>
    /// Content-addressed, so the client can compute the same tag for bytes it uploaded itself and
    /// skip a round trip it already knows the answer to.
    /// </summary>
    private static string ETagFor(byte[] photo) =>
        $"\"{Convert.ToHexStringLower(SHA256.HashData(photo))}\"";

    private static async Task<(IResult? Failure, Guid UserId)> AuthoriseAsync(
        HttpContext http,
        KvittaDbContext db,
        Guid groupId,
        CancellationToken cancellationToken)
    {
        if (!CallerId.TryRead(http, out var userId))
        {
            return (Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized), default);
        }

        var isMember = await db.Members
            .Where(member => member.GroupId == groupId)
            .AnyAsync(Membership.Authorising(userId), cancellationToken);

        if (!isMember)
        {
            return (Results.Problem(
                title: "Not a member",
                detail: $"User {userId} is not a member of group {groupId}.",
                statusCode: StatusCodes.Status403Forbidden), default);
        }

        return (null, userId);
    }
}
