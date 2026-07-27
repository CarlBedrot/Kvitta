using System.Text.Json;
using Kvitta.Api.Domain;

namespace Kvitta.Api.Validation;

/// <summary>
/// Who a group member may be attached to.
/// </summary>
/// <remarks>
/// A member is either a placeholder — someone in the group who never installed the app, design doc
/// §5 — or linked to the user adding them. Nothing else. Before M4 a client could name any user id
/// at all in a <c>MemberAdded</c>, and the server would create a <c>users</c> row for it on the
/// spot, which meant any caller could invent accounts and claim other people were members of groups
/// they had never heard of.
///
/// Linking someone *else* is what invites are for (§7), and that is decided server-side in M4b
/// against a token the invitee actually holds — never by a client asserting it.
/// </remarks>
public static class MemberLinkValidator
{
    public static ValidationResult Validate(EventEnvelope envelope, Guid callerId)
    {
        if (envelope.Type != EventTypes.MemberAdded)
        {
            return ValidationResult.Valid;
        }

        if (!TryReadLinkedUserId(envelope.Payload, out var linkedUserId))
        {
            // A placeholder member. The overwhelmingly common case: everyone in the group except
            // whoever created it.
            return ValidationResult.Valid;
        }

        if (linkedUserId != callerId)
        {
            return ValidationResult.Reject(
                RejectionCode.UnauthorizedLink,
                $"A member may only be linked to the caller; this one names {linkedUserId}.");
        }

        return ValidationResult.Valid;
    }

    /// <summary>False for absent, null, or unparseable — all of which mean "placeholder".</summary>
    public static bool TryReadLinkedUserId(JsonElement payload, out Guid linkedUserId)
    {
        linkedUserId = Guid.Empty;

        return payload.ValueKind == JsonValueKind.Object
            && payload.TryGetProperty("linkedUserId", out var linked)
            && linked.ValueKind == JsonValueKind.String
            && Guid.TryParse(linked.GetString(), out linkedUserId);
    }
}
