using System.Text.Json;
using System.Text.Json.Nodes;
using Kvitta.Api.Auth;
using Kvitta.Api.Data;
using Kvitta.Api.Domain;
using Kvitta.Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Kvitta.Api.Endpoints;

public sealed record CreateInviteResponse(Guid Token, DateTimeOffset ExpiresAt, string Url);

public sealed record AcceptInviteRequest(Guid? MemberId, string? DisplayName);

public sealed record AcceptInviteResponse(Guid GroupId, Guid MemberId);

/// <summary>
/// Invite links (design doc §7): a token URL that, when accepted, creates or links a Member.
/// </summary>
public static class InviteEndpoints
{
    public static void MapInviteEndpoints(this IEndpointRouteBuilder routes)
    {
        routes.MapPost("/api/v1/groups/{groupId:guid}/invites", CreateAsync);
        routes.MapPost("/api/v1/invites/{token:guid}/accept", AcceptAsync);
    }

    /// <summary>Mints an invite for a group. Members only — you cannot invite yourself in.</summary>
    private static async Task<IResult> CreateAsync(
        Guid groupId,
        HttpContext http,
        KvittaDbContext db,
        IOptions<AuthOptions> authOptions,
        TimeProvider time,
        CancellationToken cancellationToken)
    {
        if (!CallerId.TryRead(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var isMember = await db.Members
            .Where(member => member.GroupId == groupId)
            .AnyAsync(Membership.Authorising(userId), cancellationToken);

        if (!isMember)
        {
            return Results.Problem(
                title: "Not a member",
                detail: $"User {userId} is not a member of group {groupId}.",
                statusCode: StatusCodes.Status403Forbidden);
        }

        var invite = new InviteRecord
        {
            Token = Guid.NewGuid(),
            GroupId = groupId,
            ExpiresAt = time.GetUtcNow().AddDays(authOptions.Value.InviteLifetimeDays),
            Revoked = false
        };

        db.Invites.Add(invite);
        await db.SaveChangesAsync(cancellationToken);

        // A custom scheme rather than a universal link, because an https link needs an
        // apple-app-site-association file on a host that does not exist until the deploy. The
        // token and this endpoint do not change when universal links land — that is additive.
        return Results.Ok(new CreateInviteResponse(
            invite.Token,
            invite.ExpiresAt,
            $"slice://invite/{invite.Token}"));
    }

    /// <summary>
    /// Accepts an invite, which links the caller to a member of that group.
    /// </summary>
    /// <remarks>
    /// This endpoint writes an event rather than having the client push one, which is a deliberate
    /// exception to "clients author events". It has to be: membership is derived from the log, so
    /// the event that makes you a member cannot itself be written by a member — a push would 403
    /// before it ever reached the log. Design doc §7 describes exactly this: "Accepting it creates
    /// or links a Member."
    ///
    /// The event is still attributed to the accepting user, because they really did do it.
    /// </remarks>
    private static async Task<IResult> AcceptAsync(
        Guid token,
        AcceptInviteRequest? request,
        HttpContext http,
        KvittaDbContext db,
        EventWriter writer,
        TimeProvider time,
        CancellationToken cancellationToken)
    {
        if (!CallerId.TryRead(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var now = time.GetUtcNow();
        var invite = await db.Invites.SingleOrDefaultAsync(
            candidate => candidate.Token == token,
            cancellationToken);

        if (invite is null)
        {
            return Results.Problem(
                title: "Unknown invite",
                detail: "That invite does not exist.",
                statusCode: StatusCodes.Status404NotFound);
        }

        if (invite.Revoked || invite.ExpiresAt <= now)
        {
            // 410 rather than 404: it did exist, and saying so is what lets the app tell someone
            // "ask for a new link" instead of "you typed it wrong".
            return Results.Problem(
                title: "Invite no longer valid",
                detail: invite.Revoked ? "That invite was revoked." : "That invite has expired.",
                statusCode: StatusCodes.Status410Gone);
        }

        // Already in the group. Idempotent: opening the same link twice must not create a second
        // member, and tapping it again after a crash must not fail.
        var existing = await db.Members
            .Where(member => member.GroupId == invite.GroupId)
            .FirstOrDefaultAsync(Membership.Authorising(userId), cancellationToken);

        if (existing is not null)
        {
            return Results.Ok(new AcceptInviteResponse(invite.GroupId, existing.Id));
        }

        var claimed = request?.MemberId;
        if (claimed is { } memberId)
        {
            var placeholder = await db.Members.SingleOrDefaultAsync(
                member => member.Id == memberId && member.GroupId == invite.GroupId,
                cancellationToken);

            if (placeholder is null || !placeholder.IsActive || placeholder.LinkedUserId is not null)
            {
                return Results.Problem(
                    title: "Cannot claim that member",
                    detail: "That member does not exist in this group, has left, or is already someone's.",
                    statusCode: StatusCodes.Status409Conflict);
            }

            return await WriteAsync(
                invite.GroupId,
                memberId,
                EventTypes.MemberUpdated,
                new JsonObject { ["linkedUserId"] = userId.ToString() },
                userId, writer, now, cancellationToken);
        }

        // Nobody to claim: join as a new member.
        var name = request?.DisplayName is { Length: > 0 } supplied
            ? supplied
            : await db.Users
                .Where(user => user.Id == userId)
                .Select(user => user.DisplayName)
                .FirstOrDefaultAsync(cancellationToken) ?? "Ny medlem";

        return await WriteAsync(
            invite.GroupId,
            Guid.NewGuid(),
            EventTypes.MemberAdded,
            new JsonObject { ["displayName"] = name, ["linkedUserId"] = userId.ToString() },
            userId, writer, now, cancellationToken);
    }

    private static async Task<IResult> WriteAsync(
        Guid groupId,
        Guid memberId,
        string type,
        JsonObject payload,
        Guid userId,
        EventWriter writer,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var raw = payload.ToJsonString();

        var envelope = new EventEnvelope
        {
            EventId = Guid.NewGuid(),
            GroupId = groupId,
            EntityId = memberId,
            Type = type,
            SchemaVersion = 1,
            AuthorId = userId,
            ClientTimestamp = now.ToString("o"),
            Payload = JsonDocument.Parse(raw).RootElement
        };

        var outcome = await writer.IngestAsync(
            groupId,
            userId,
            [envelope],
            [raw],
            cancellationToken,
            PushAuthorisation.AcceptedInvite);

        if (outcome.Rejected.Count > 0)
        {
            var rejection = outcome.Rejected[0];
            return Results.Problem(
                title: "Could not join",
                detail: $"{rejection.Code}: {rejection.Reason}",
                statusCode: StatusCodes.Status422UnprocessableEntity);
        }

        return Results.Ok(new AcceptInviteResponse(groupId, memberId));
    }
}
