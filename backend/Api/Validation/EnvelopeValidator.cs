using System.Text;
using System.Text.Json;
using Kvitta.Api.Domain;

namespace Kvitta.Api.Validation;

/// <summary>
/// Shape checks that apply to every event, whatever its type.
/// </summary>
/// <remarks>
/// An event whose <c>type</c> this build does not recognise passes here and is stored verbatim,
/// with no payload validation. That is deliberate and it is worth being explicit about, because
/// CLAUDE.md says the server validates everything it stores.
///
/// The design doc calls this server "a dumb, boring sync and fan-out layer", and §9 requires new
/// event types not to break old readers. Rejecting unknown types would make every new event type
/// a server deploy that must land *before* any client that emits one — and a TestFlight build
/// that got ahead of the server would have its events refused permanently, with nothing the user
/// could do. Meanwhile an unknown type cannot move money: every client skips it when projecting,
/// so it contributes to no balance anywhere. Accepting costs nothing; rejecting strands data.
/// </remarks>
public static class EnvelopeValidator
{
    public static ValidationResult Validate(
        EventEnvelope envelope,
        Guid pathGroupId,
        string rawPayload,
        int maxPayloadBytes)
    {
        if (envelope.EventId == Guid.Empty)
        {
            return ValidationResult.Reject(RejectionCode.MalformedEnvelope, "eventId is missing.");
        }

        if (envelope.GroupId != pathGroupId)
        {
            return ValidationResult.Reject(
                RejectionCode.GroupMismatch,
                $"Event names group {envelope.GroupId} but was pushed to {pathGroupId}.");
        }

        if (envelope.AuthorId == Guid.Empty)
        {
            return ValidationResult.Reject(RejectionCode.MalformedEnvelope, "authorId is missing.");
        }

        if (string.IsNullOrWhiteSpace(envelope.Type))
        {
            return ValidationResult.Reject(RejectionCode.MalformedEnvelope, "type is missing.");
        }

        if (envelope.SchemaVersion < 1)
        {
            return ValidationResult.Reject(
                RejectionCode.MalformedEnvelope,
                $"schemaVersion must be at least 1, got {envelope.SchemaVersion}.");
        }

        if (string.IsNullOrWhiteSpace(envelope.ClientTimestamp) ||
            !DateTimeOffset.TryParse(envelope.ClientTimestamp, out _))
        {
            return ValidationResult.Reject(
                RejectionCode.MalformedEnvelope,
                "clientTimestamp is missing or not a timestamp.");
        }

        if (envelope.Payload.ValueKind is JsonValueKind.Undefined)
        {
            return ValidationResult.Reject(RejectionCode.MalformedEnvelope, "payload is missing.");
        }

        var size = Encoding.UTF8.GetByteCount(rawPayload);
        if (size > maxPayloadBytes)
        {
            return ValidationResult.Reject(
                RejectionCode.PayloadTooLarge,
                $"Payload is {size} bytes; the limit is {maxPayloadBytes}.");
        }

        return ValidationResult.Valid;
    }
}
