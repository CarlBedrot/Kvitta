using System.Text.Json;
using System.Text.Json.Serialization;

namespace Kvitta.Api.Domain;

/// <summary>
/// One entry in a group's event log, exactly as the iOS client encodes it (design doc §2).
/// </summary>
/// <remarks>
/// The payload stays as raw <see cref="JsonElement"/> rather than a typed union. The server only
/// needs to understand a payload well enough to validate it; everything else it stores verbatim
/// and hands back untouched. That is what lets a client emit an event type this build has never
/// heard of without a server deploy having to land first.
/// </remarks>
public sealed record EventEnvelope
{
    [JsonPropertyName("eventId")]
    public Guid EventId { get; init; }

    [JsonPropertyName("groupId")]
    public Guid GroupId { get; init; }

    [JsonPropertyName("entityId")]
    public Guid EntityId { get; init; }

    [JsonPropertyName("type")]
    public string Type { get; init; } = "";

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; init; } = 1;

    [JsonPropertyName("authorId")]
    public Guid AuthorId { get; init; }

    /// <summary>Display only. Never used for ordering — that is <c>serverSeq</c>'s job.</summary>
    [JsonPropertyName("clientTimestamp")]
    public string ClientTimestamp { get; init; } = "";

    /// <summary>Assigned here, on ingest. Null on the way in.</summary>
    [JsonPropertyName("serverSeq")]
    public long? ServerSeq { get; init; }

    [JsonPropertyName("payload")]
    public JsonElement Payload { get; init; }
}

/// <summary>The event type strings, mirroring KvittaCore's <c>EventType</c>.</summary>
public static class EventTypes
{
    public const string GroupCreated = "GroupCreated";
    public const string GroupUpdated = "GroupUpdated";
    public const string MemberAdded = "MemberAdded";
    public const string MemberUpdated = "MemberUpdated";
    public const string MemberRemoved = "MemberRemoved";
    public const string ExpenseCreated = "ExpenseCreated";
    public const string ExpenseUpdated = "ExpenseUpdated";
    public const string ExpenseDeleted = "ExpenseDeleted";
    public const string ExpenseRestored = "ExpenseRestored";
    public const string PaymentRecorded = "PaymentRecorded";
}
