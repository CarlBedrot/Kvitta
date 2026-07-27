using System.Text.Json;
using Kvitta.Api.Domain;
using Kvitta.Api.Options;
using Kvitta.Api.Validation;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Kvitta.Api.Data;

public readonly record struct AcceptedEvent(Guid EventId, long ServerSeq);

public readonly record struct RejectedEvent(Guid EventId, string Code, string Reason);

public sealed record PushOutcome(
    IReadOnlyList<AcceptedEvent> Accepted,
    IReadOnlyList<RejectedEvent> Rejected)
{
    public static PushOutcome Empty { get; } = new([], []);
}

/// <summary>Raised when the caller is not entitled to write to this group at all.</summary>
public sealed class NotAMemberException(string reason) : Exception(reason);

/// <summary>
/// Ingests a batch of events into one group's log.
/// </summary>
/// <remarks>
/// The whole batch runs inside one transaction that begins by taking a row lock on the group
/// (§8). That lock is what makes <c>serverSeq</c> gap-free and strictly ordered without any
/// sequence-reservation cleverness: at this write volume, serialising writers per group costs
/// nothing and it keeps the client's cursor logic trivial.
///
/// Events are accepted or rejected individually. A batch is an outbox drain, and if one bad event
/// failed the whole batch it would sit at the head of that outbox forever, blocking every good
/// event behind it.
/// </remarks>
public sealed class EventWriter(KvittaDbContext db, IOptions<SyncOptions> syncOptions)
{
    private readonly SyncOptions _sync = syncOptions.Value;

    public async Task<PushOutcome> IngestAsync(
        Guid groupId,
        Guid userId,
        IReadOnlyList<EventEnvelope> events,
        IReadOnlyList<string> rawPayloads,
        CancellationToken cancellationToken)
    {
        if (events.Count == 0)
        {
            return PushOutcome.Empty;
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        await EnsureUserExistsAsync(userId, cancellationToken);

        var bootstrapping = await LockOrBootstrapGroupAsync(groupId, events[0], cancellationToken);
        var group = await db.Groups.SingleAsync(candidate => candidate.Id == groupId, cancellationToken);

        var members = await db.Members
            .Where(member => member.GroupId == groupId)
            .ToListAsync(cancellationToken);

        // Authorization. M4 replaces the trusted header with a verified JWT subject; the rule
        // itself does not change. The bootstrap case exists because the very first push to a new
        // group necessarily arrives before its author is a member of anything.
        var isMember = members.Any(member => member.LinkedUserId == userId);
        if (!bootstrapping && !isMember)
        {
            throw new NotAMemberException($"User {userId} is not a member of group {groupId}.");
        }

        var knownMembers = members.Select(member => member.Id).ToHashSet();
        var nextSeq = await NextServerSeqAsync(groupId, cancellationToken);

        var accepted = new List<AcceptedEvent>(events.Count);
        var rejected = new List<RejectedEvent>();

        // Users a MemberAdded links to. Collected rather than inserted inline: the pushing user is
        // usually one of them, and EF would happily issue a second INSERT for a row the upsert
        // above already created.
        var linkedUsers = new HashSet<Guid>();

        for (var index = 0; index < events.Count; index++)
        {
            var envelope = events[index];
            var raw = rawPayloads[index];

            var envelopeCheck = EnvelopeValidator.Validate(envelope, groupId, raw, _sync.MaxPayloadBytes);
            if (!envelopeCheck.IsValid)
            {
                rejected.Add(new RejectedEvent(envelope.EventId, envelopeCheck.Code!, envelopeCheck.Reason!));
                continue;
            }

            // Idempotency, before any validation that could have changed since first ingest:
            // an event already in the log keeps the sequence it was originally given.
            var existingSeq = await db.Events
                .Where(record => record.EventId == envelope.EventId)
                .Select(record => (long?)record.ServerSeq)
                .FirstOrDefaultAsync(cancellationToken);

            if (existingSeq is { } seq)
            {
                accepted.Add(new AcceptedEvent(envelope.EventId, seq));
                continue;
            }

            var moneyCheck = MoneyValidator.Validate(
                envelope.Type,
                envelope.Payload,
                group.Currency ?? "",
                knownMembers);

            if (!moneyCheck.IsValid)
            {
                rejected.Add(new RejectedEvent(envelope.EventId, moneyCheck.Code!, moneyCheck.Reason!));
                continue;
            }

            db.Events.Add(new EventRecord
            {
                GroupId = groupId,
                ServerSeq = nextSeq,
                EventId = envelope.EventId,
                EntityId = envelope.EntityId,
                Type = envelope.Type,
                SchemaVersion = envelope.SchemaVersion,
                AuthorId = envelope.AuthorId,
                ClientTimestamp = envelope.ClientTimestamp,
                Payload = raw,
                ReceivedAt = DateTimeOffset.UtcNow
            });

            ApplyDerivedState(envelope, group, members, knownMembers, linkedUsers);

            accepted.Add(new AcceptedEvent(envelope.EventId, nextSeq));
            nextSeq++;
        }

        // Before SaveChanges, because the members rows about to be inserted have an FK to these.
        foreach (var linkedUserId in linkedUsers)
        {
            await EnsureUserExistsAsync(linkedUserId, cancellationToken);
        }

        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return new PushOutcome(accepted, rejected);
    }

    /// <summary>
    /// Maintains the two derived caches — membership and group currency — as events land.
    /// Deliberately not a projection: no balances are computed here and none ever should be (§4).
    /// </summary>
    private void ApplyDerivedState(
        EventEnvelope envelope,
        GroupRecord group,
        List<MemberRecord> members,
        HashSet<Guid> knownMembers,
        HashSet<Guid> linkedUsers)
    {
        switch (envelope.Type)
        {
            case EventTypes.GroupCreated or EventTypes.GroupUpdated:
                if (envelope.Payload.ValueKind == JsonValueKind.Object &&
                    envelope.Payload.TryGetProperty("currency", out var currency) &&
                    currency.ValueKind == JsonValueKind.String)
                {
                    group.Currency = currency.GetString();
                }

                break;

            case EventTypes.MemberAdded:
                if (knownMembers.Add(envelope.EntityId))
                {
                    Guid? linkedUserId = null;
                    if (envelope.Payload.ValueKind == JsonValueKind.Object &&
                        envelope.Payload.TryGetProperty("linkedUserId", out var linked) &&
                        linked.ValueKind == JsonValueKind.String &&
                        Guid.TryParse(linked.GetString(), out var parsed))
                    {
                        linkedUserId = parsed;
                    }

                    var displayName = "";
                    if (envelope.Payload.ValueKind == JsonValueKind.Object &&
                        envelope.Payload.TryGetProperty("displayName", out var name) &&
                        name.ValueKind == JsonValueKind.String)
                    {
                        displayName = name.GetString() ?? "";
                    }

                    var record = new MemberRecord
                    {
                        Id = envelope.EntityId,
                        GroupId = group.Id,
                        LinkedUserId = linkedUserId,
                        DisplayName = displayName
                    };
                    members.Add(record);
                    db.Members.Add(record);

                    if (linkedUserId is { } userId)
                    {
                        // A member can name a user this server has never seen — that user's own
                        // device has not pushed yet. The row gets upserted before SaveChanges so
                        // the FK holds; M4 fills in the Apple identity when they actually sign in.
                        linkedUsers.Add(userId);
                    }
                }

                break;

            case EventTypes.MemberRemoved:
                var removed = members.FirstOrDefault(member => member.Id == envelope.EntityId);
                if (removed is not null)
                {
                    removed.IsActive = false;
                }

                break;
        }
    }

    /// <summary>
    /// Takes the group's row lock, creating the group first if this batch legitimately bootstraps
    /// it. Returns whether this call is the bootstrap.
    /// </summary>
    private async Task<bool> LockOrBootstrapGroupAsync(
        Guid groupId,
        EventEnvelope first,
        CancellationToken cancellationToken)
    {
        var exists = await LockGroupRowAsync(groupId, cancellationToken);
        if (exists)
        {
            return false;
        }

        if (first.Type != EventTypes.GroupCreated)
        {
            throw new NotAMemberException(
                $"Group {groupId} does not exist and this batch does not open with {EventTypes.GroupCreated}.");
        }

        // ON CONFLICT keeps two simultaneous bootstraps from both inserting; whichever loses
        // simply proceeds against the row the winner made.
        await db.Database.ExecuteSqlInterpolatedAsync(
            $"INSERT INTO groups (\"Id\", \"CreatedAt\") VALUES ({groupId}, {DateTimeOffset.UtcNow}) ON CONFLICT (\"Id\") DO NOTHING",
            cancellationToken);

        await LockGroupRowAsync(groupId, cancellationToken);
        return true;
    }

    private async Task<bool> LockGroupRowAsync(Guid groupId, CancellationToken cancellationToken)
    {
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var command = connection.CreateCommand();
        command.Transaction = (NpgsqlTransaction?)db.Database.CurrentTransaction?.GetDbTransaction();
        command.CommandText = "SELECT 1 FROM groups WHERE \"Id\" = @id FOR UPDATE";
        command.Parameters.AddWithValue("id", groupId);

        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is not null;
    }

    private async Task<long> NextServerSeqAsync(Guid groupId, CancellationToken cancellationToken)
    {
        // Safe under the row lock taken above: no other writer for this group can be between the
        // read and our inserts.
        var highest = await db.Events
            .Where(record => record.GroupId == groupId)
            .MaxAsync(record => (long?)record.ServerSeq, cancellationToken);

        return (highest ?? 0) + 1;
    }

    private async Task EnsureUserExistsAsync(Guid userId, CancellationToken cancellationToken)
    {
        await db.Database.ExecuteSqlInterpolatedAsync(
            $"INSERT INTO users (\"Id\", \"CreatedAt\") VALUES ({userId}, {DateTimeOffset.UtcNow}) ON CONFLICT (\"Id\") DO NOTHING",
            cancellationToken);
    }
}
