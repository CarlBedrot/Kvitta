namespace Kvitta.Api.Data;

/// <summary>
/// Design doc §8's tables. Only <c>events</c> holds truth; the rest is anchors and derived state.
/// </summary>
public sealed class UserRecord
{
    public Guid Id { get; set; }

    /// <summary>
    /// Apple's stable subject for this app. The only way a user row is created.
    /// </summary>
    /// <remarks>
    /// Nullable only because rows predating M4 exist. Nothing creates a null one any more — the
    /// blind upsert that used to mint a row for any GUID a client mentioned is gone.
    /// </remarks>
    public string? AppleSub { get; set; }

    public string? DisplayName { get; set; }

    /// <summary>
    /// The number people Swish this user on, digits with country code (<c>46701234567</c>).
    /// </summary>
    /// <remarks>
    /// A mutable profile column and deliberately not an event: events are immutable, so a phone
    /// number in a group log would reach every member forever with no way to take it back. Here
    /// the owner can change or delete it and it simply stops being served.
    /// </remarks>
    public string? SwishNumber { get; set; }

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
/// One link in a refresh-token chain (design doc §7).
/// </summary>
/// <remarks>
/// Stored as a SHA-256 of 32 CSPRNG bytes. A hash and not a slow KDF on purpose: the token is
/// already 256 bits of randomness, so there is no pre-image to guess and bcrypt would buy nothing
/// but latency on every refresh.
///
/// <c>FamilyId</c> is what makes theft survivable. Every rotation stays in the same family, so
/// presenting a token that has already been used means either a thief or a confused client — and
/// the only safe response is to revoke the whole chain, including whatever the current holder has.
/// </remarks>
public sealed class RefreshTokenRecord
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    public byte[] TokenHash { get; set; } = [];

    /// <summary>Constant across one rotation chain.</summary>
    public Guid FamilyId { get; set; }

    /// <summary>The link this one replaced. Forensics only — nothing reads it to make a decision.</summary>
    public Guid? ParentId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>Absolute. Rotation issues a successor but never extends the deadline.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>Set when rotated. A second presentation after this is set is the reuse signal.</summary>
    public DateTimeOffset? UsedAt { get; set; }

    public DateTimeOffset? RevokedAt { get; set; }

    /// <summary>One of <c>rotated</c>, <c>reuse_detected</c>, <c>signed_out</c>.</summary>
    public string? RevokedReason { get; set; }
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
