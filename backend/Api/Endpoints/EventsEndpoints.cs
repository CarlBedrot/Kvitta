using System.Text.Json;
using System.Text.Json.Nodes;
using Kvitta.Api.Data;
using Kvitta.Api.Domain;
using Kvitta.Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Kvitta.Api.Endpoints;

public sealed record PushResponse(
    IReadOnlyList<AcceptedEvent> Accepted,
    IReadOnlyList<RejectedEvent> Rejected);

public sealed record PullResponse(IReadOnlyList<JsonNode> Events, long NextCursor);

public sealed record GroupListResponse(IReadOnlyList<Guid> GroupIds);

public static class EventsEndpoints
{
    public const string BuildHeader = "X-Kvitta-Build";

    public static void MapEventEndpoints(this IEndpointRouteBuilder routes)
    {
        routes.MapGet("/api/v1/groups", ListGroupsAsync);

        var group = routes.MapGroup("/api/v1/groups/{groupId:guid}/events");

        group.MapPost("/", PushAsync);
        group.MapGet("/", PullAsync);
    }

    /// <summary>
    /// The groups this user belongs to.
    /// </summary>
    /// <remarks>
    /// Design doc §6's "new device / reinstall" case needs this and nothing else does: a client
    /// with an empty database has no idea which groups to pull, so without this endpoint a
    /// reinstall silently shows an empty app while the events sit here untouched. It returns ids
    /// only — names and everything else still live in the log, per §8.
    /// </remarks>
    private static async Task<IResult> ListGroupsAsync(
        HttpContext http,
        KvittaDbContext db,
        IOptions<SyncOptions> syncOptions,
        CancellationToken cancellationToken)
    {
        if (RequiresUpgrade(http, syncOptions.Value, out var upgrade))
        {
            return upgrade;
        }

        if (!TryReadUserId(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var groupIds = await db.Members
            .Where(Membership.Authorising(userId))
            .Select(member => member.GroupId)
            .Distinct()
            .ToListAsync(cancellationToken);

        return Results.Ok(new GroupListResponse(groupIds));
    }

    /// <summary>
    /// Push an outbox batch, in client order (§6).
    /// </summary>
    /// <remarks>
    /// Returns 200 with per-event outcomes rather than a single status, because a batch can
    /// legitimately be part good and part bad and there is no honest status code for that. The
    /// client acknowledges what was accepted and surfaces what was not.
    /// </remarks>
    private static async Task<IResult> PushAsync(
        Guid groupId,
        HttpContext http,
        JsonElement body,
        EventWriter writer,
        IOptions<SyncOptions> syncOptions,
        CancellationToken cancellationToken)
    {
        if (RequiresUpgrade(http, syncOptions.Value, out var upgrade))
        {
            return upgrade;
        }

        if (!TryReadUserId(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        if (body.ValueKind != JsonValueKind.Array)
        {
            return Results.Problem(
                title: "Malformed body",
                detail: "Expected a JSON array of event envelopes.",
                statusCode: StatusCodes.Status400BadRequest);
        }

        var sync = syncOptions.Value;
        var envelopes = new List<EventEnvelope>();
        var rawPayloads = new List<string>();

        foreach (var element in body.EnumerateArray())
        {
            EventEnvelope? envelope;
            try
            {
                envelope = element.Deserialize<EventEnvelope>();
            }
            catch (JsonException exception)
            {
                return Results.Problem(
                    title: "Malformed body",
                    detail: exception.Message,
                    statusCode: StatusCodes.Status400BadRequest);
            }

            if (envelope is null)
            {
                return Results.Problem(
                    title: "Malformed body",
                    detail: "An element of the batch was null.",
                    statusCode: StatusCodes.Status400BadRequest);
            }

            envelopes.Add(envelope);

            // Kept as the client's own bytes. Re-serialising would risk quietly dropping fields
            // of an event type this build does not model.
            rawPayloads.Add(
                envelope.Payload.ValueKind == JsonValueKind.Undefined
                    ? "{}"
                    : envelope.Payload.GetRawText());
        }

        if (envelopes.Count > sync.MaxPushBatchSize)
        {
            return Results.Problem(
                title: "Batch too large",
                detail: $"{envelopes.Count} events exceeds the limit of {sync.MaxPushBatchSize}.",
                statusCode: StatusCodes.Status422UnprocessableEntity);
        }

        try
        {
            var outcome = await writer.IngestAsync(groupId, userId, envelopes, rawPayloads, cancellationToken);
            return Results.Ok(new PushResponse(outcome.Accepted, outcome.Rejected));
        }
        catch (NotAMemberException exception)
        {
            return Results.Problem(
                title: "Not a member",
                detail: exception.Message,
                statusCode: StatusCodes.Status403Forbidden);
        }
    }

    /// <summary>
    /// Pull everything after a cursor, in <c>serverSeq</c> order (§6).
    /// </summary>
    private static async Task<IResult> PullAsync(
        Guid groupId,
        HttpContext http,
        long? after,
        int? limit,
        KvittaDbContext db,
        IOptions<SyncOptions> syncOptions,
        CancellationToken cancellationToken)
    {
        if (RequiresUpgrade(http, syncOptions.Value, out var upgrade))
        {
            return upgrade;
        }

        if (!TryReadUserId(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var groupExists = await db.Groups.AnyAsync(record => record.Id == groupId, cancellationToken);
        if (!groupExists)
        {
            return Results.Problem(
                title: "Unknown group",
                detail: $"No group {groupId}.",
                statusCode: StatusCodes.Status404NotFound);
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

        var cursor = after ?? 0;
        var pageSize = Math.Clamp(limit ?? syncOptions.Value.MaxPullLimit, 1, syncOptions.Value.MaxPullLimit);

        var records = await db.Events
            .Where(record => record.GroupId == groupId && record.ServerSeq > cursor)
            .OrderBy(record => record.ServerSeq)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var events = records.Select(ToEnvelopeJson).ToList();
        var nextCursor = records.Count > 0 ? records[^1].ServerSeq : cursor;

        return Results.Ok(new PullResponse(events, nextCursor));
    }

    /// <summary>
    /// Rebuilds the wire envelope around the stored payload, which is passed through untouched so
    /// an event type this build does not understand reaches the client exactly as it arrived.
    /// </summary>
    private static JsonNode ToEnvelopeJson(EventRecord record) => new JsonObject
    {
        ["eventId"] = record.EventId.ToString(),
        ["groupId"] = record.GroupId.ToString(),
        ["entityId"] = record.EntityId.ToString(),
        ["type"] = record.Type,
        ["schemaVersion"] = record.SchemaVersion,
        ["authorId"] = record.AuthorId.ToString(),
        ["clientTimestamp"] = record.ClientTimestamp,
        ["serverSeq"] = record.ServerSeq,
        ["payload"] = JsonNode.Parse(record.Payload)
    };

    /// <summary>
    /// The authenticated caller, from the access token this server signed.
    /// </summary>
    /// <remarks>
    /// This used to read <c>X-Kvitta-User-Id</c> and believe it, which meant anyone who could set
    /// a header was anyone they liked. The subject now comes from a token validated by the JWT
    /// bearer handler.
    ///
    /// Reading <c>sub</c> literally only works because <c>MapInboundClaims</c> is off in
    /// <c>Program.cs</c>; with the default on, the handler renames it to
    /// <c>ClaimTypes.NameIdentifier</c> and this returns false for every authenticated request.
    /// </remarks>
    private static bool TryReadUserId(HttpContext http, out Guid userId)
    {
        userId = Guid.Empty;
        var subject = http.User.FindFirst("sub")?.Value;
        return subject is not null && Guid.TryParse(subject, out userId);
    }

    /// <summary>Design doc §9's forced-update escape hatch.</summary>
    private static bool RequiresUpgrade(HttpContext http, SyncOptions sync, out IResult result)
    {
        result = Results.Empty;

        if (sync.MinimumClientBuild <= 0)
        {
            return false;
        }

        var build = 0;
        if (http.Request.Headers.TryGetValue(BuildHeader, out var raw))
        {
            _ = int.TryParse(raw.ToString(), out build);
        }

        if (build >= sync.MinimumClientBuild)
        {
            return false;
        }

        result = Results.Problem(
            title: "Upgrade required",
            detail: $"This build ({build}) is below the minimum supported build ({sync.MinimumClientBuild}).",
            statusCode: StatusCodes.Status426UpgradeRequired);

        return true;
    }
}
