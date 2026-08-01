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

/// <summary>What entitles this write.</summary>
/// <remarks>
/// An enum rather than a boolean flag, because the second case switches off the membership check
/// and that should be impossible to pass by accident — and easy to grep for.
///
/// <see cref="AcceptedInvite"/> exists because of a genuine chicken-and-egg: membership is derived
/// from the log, so the event that makes you a member cannot itself be written by a member. The
/// only caller is the invite-acceptance endpoint, and only after it has validated a token the
/// user actually holds.
/// </remarks>
public enum PushAuthorisation
{
    Membership,
    AcceptedInvite
}

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
public sealed class EventWriter(
    KvittaDbContext db,
    IOptions<SyncOptions> syncOptions,
    ILogger<EventWriter> logger)
{
    private readonly SyncOptions _sync = syncOptions.Value;

    public async Task<PushOutcome> IngestAsync(
        Guid groupId,
        Guid userId,
        IReadOnlyList<EventEnvelope> events,
        IReadOnlyList<string> rawPayloads,
        CancellationToken cancellationToken,
        PushAuthorisation authorisation = PushAuthorisation.Membership)
    {
        // Returns before authorization, deliberately. An empty batch cannot write anything, so
        // there is nothing to authorise and no transaction worth opening — and because the answer
        // is the same for members and strangers alike, it is not a membership oracle either.
        // `A_stranger_pushing_nothing_writes_nothing` pins that, so this stays a considered
        // shortcut rather than something a later reader mistakes for a gap.
        if (events.Count == 0)
        {
            return PushOutcome.Empty;
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        // No user upsert here any more. The caller's row is created by POST /api/v1/auth/apple and
        // by nothing else, so a user row now means "someone who has actually signed in" rather
        // than "a GUID somebody once mentioned".
        var bootstrapping = await LockOrBootstrapGroupAsync(groupId, events, userId, cancellationToken);
        var group = await db.Groups.SingleAsync(candidate => candidate.Id == groupId, cancellationToken);

        var members = await db.Members
            .Where(member => member.GroupId == groupId)
            .ToListAsync(cancellationToken);

        // Authorization. M4 replaces the trusted header with a verified JWT subject; the rule
        // itself does not change. The bootstrap case exists because the very first push to a new
        // group necessarily arrives before its author is a member of anything.
        //
        // Checked before the loop, so a batch that removes the caller still lands: they were a
        // member when it was written, and events are immutable.
        var isMember = Membership.IsAuthorised(members, userId)
            || authorisation == PushAuthorisation.AcceptedInvite;

        if (!bootstrapping && !isMember)
        {
            throw new NotAMemberException($"User {userId} is not a member of group {groupId}.");
        }

        var knownMembers = members.Select(member => member.Id).ToHashSet();
        var nextSeq = await NextServerSeqAsync(groupId, cancellationToken);

        var accepted = new List<AcceptedEvent>(events.Count);
        var rejected = new List<RejectedEvent>();

        for (var index = 0; index < events.Count; index++)
        {
            var envelope = events[index];
            var raw = rawPayloads[index];

            var envelopeCheck = EnvelopeValidator.Validate(envelope, groupId, userId, raw, _sync.MaxPayloadBytes);
            if (!envelopeCheck.IsValid)
            {
                rejected.Add(new RejectedEvent(envelope.EventId, envelopeCheck.Code!, envelopeCheck.Reason!));
                continue;
            }

            var linkCheck = MemberLinkValidator.Validate(envelope, userId);
            if (!linkCheck.IsValid)
            {
                rejected.Add(new RejectedEvent(envelope.EventId, linkCheck.Code!, linkCheck.Reason!));
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

            ApplyDerivedState(envelope, group, members, knownMembers);

            accepted.Add(new AcceptedEvent(envelope.EventId, nextSeq));
            nextSeq++;
        }

        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        if (rejected.Count > 0)
        {
            // Codes and ids only — payloads are the group's money history and do not belong in
            // logs. This is the server-side half of "never drop events silently": the client
            // shows each rejection to its user, and this line shows the pattern to the operator.
            logger.LogWarning(
                "Rejected {Count} of {Total} events in group {GroupId}: {Codes}",
                rejected.Count,
                events.Count,
                groupId,
                string.Join(", ", rejected.Select(r => $"{r.EventId}:{r.Code}")));
        }

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
        HashSet<Guid> knownMembers)
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
                    // Already validated to be either absent or the caller, whose users row exists.
                    Guid? linkedUserId = MemberLinkValidator.TryReadLinkedUserId(envelope.Payload, out var parsed)
                        ? parsed
                        : null;

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
                }

                break;

            case EventTypes.MemberUpdated:
                var updated = members.FirstOrDefault(member => member.Id == envelope.EntityId);
                if (updated is not null)
                {
                    // Absent means unchanged, matching the client's projector. Nothing here can
                    // move money: a member's identity and their balance are independent, which is
                    // what lets someone join months late and inherit a history that already adds up.
                    if (MemberLinkValidator.TryReadLinkedUserId(envelope.Payload, out var linked))
                    {
                        updated.LinkedUserId = linked;
                    }

                    if (envelope.Payload.ValueKind == JsonValueKind.Object &&
                        envelope.Payload.TryGetProperty("displayName", out var newName) &&
                        newName.ValueKind == JsonValueKind.String)
                    {
                        updated.DisplayName = newName.GetString() ?? updated.DisplayName;
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
        IReadOnlyList<EventEnvelope> events,
        Guid userId,
        CancellationToken cancellationToken)
    {
        var exists = await LockGroupRowAsync(groupId, cancellationToken);
        if (exists)
        {
            return false;
        }

        if (events[0].Type != EventTypes.GroupCreated)
        {
            throw new NotAMemberException(
                $"Group {groupId} does not exist and this batch does not open with {EventTypes.GroupCreated}.");
        }

        // The batch that creates a group must also put its creator in it. Membership is derived
        // from the log, so a bootstrap without this leaves the group with no members the caller is
        // linked to — the push succeeds and then every subsequent one from the same person is 403,
        // which looks exactly like a server bug from the outside.
        var linksCaller = events.Any(envelope =>
            envelope.Type is EventTypes.MemberAdded or EventTypes.MemberUpdated
            && MemberLinkValidator.TryReadLinkedUserId(envelope.Payload, out var linked)
            && linked == userId);

        if (!linksCaller)
        {
            throw new NotAMemberException(
                $"A batch creating group {groupId} must add a member linked to {userId}.");
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

}
