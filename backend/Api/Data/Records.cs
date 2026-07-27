namespace Kvitta.Api.Data;

/// <summary>
/// Design doc §8's tables. Only <c>events</c> holds truth; the rest is anchors and derived state.
/// </summary>
public sealed class UserRecord
{
    public Guid Id { get; set; }

    /// <summary>Null until Sign in with Apple lands in M4. Until then a user is just an id.</summary>
    public string? AppleSub { get; set; }

    public string? DisplayName { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

/// <summary>
/// The lock anchor. §8 keeps name and other group facts in the log, not in columns.
/// </summary>
public sealed class GroupRecord
{
    public Guid Id { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>
    /// A derived cache, not a source of truth — the log is still authoritative. It lives here
    /// because the server has to reject an expense whose currency does not match the group's, and
    /// re-reading GroupCreated out of the log on every push would be a query for a value that in
    /// practice never changes. Same justification as §8 keeping a <c>members</c> table.
    /// </summary>
    public string? Currency { get; set; }
}

/// <summary>
/// Membership, derived from MemberAdded/MemberRemoved as they are ingested.
/// This is authorization data — it is why §8 has this table — not a balance projection.
/// </summary>
public sealed class MemberRecord
{
    public Guid Id { get; set; }
    public Guid GroupId { get; set; }

    /// <summary>Null for a placeholder member: someone in the group who never installed the app (§5).</summary>
    public Guid? LinkedUserId { get; set; }

    public string DisplayName { get; set; } = "";

    /// <summary>A removed member keeps their row; balances still reference them.</summary>
    public bool IsActive { get; set; } = true;
}

/// <summary>Unused until M4. Present so the schema matches §8 and invites need no migration then.</summary>
public sealed class InviteRecord
{
    public Guid Token { get; set; }
    public Guid GroupId { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public bool Revoked { get; set; }
}

/// <summary>
/// The log. Append-only: nothing here is ever updated after insert.
/// </summary>
public sealed class EventRecord
{
    public Guid GroupId { get; set; }

    /// <summary>Assigned under the group row lock. Strictly increasing and gap-free per group.</summary>
    public long ServerSeq { get; set; }

    /// <summary>Client-generated. The unique index on this column is the whole of push idempotency.</summary>
    public Guid EventId { get; set; }

    public Guid EntityId { get; set; }
    public string Type { get; set; } = "";
    public int SchemaVersion { get; set; }
    public Guid AuthorId { get; set; }
    public string ClientTimestamp { get; set; } = "";

    /// <summary>
    /// The payload exactly as the client sent it, stored as jsonb. Never re-serialised, so an
    /// event type this build does not understand survives a round trip intact.
    /// </summary>
    public string Payload { get; set; } = "{}";

    public DateTimeOffset ReceivedAt { get; set; }
}
