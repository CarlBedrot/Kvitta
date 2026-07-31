using System.Text.Json;
using Kvitta.Api.Domain;

namespace Kvitta.Api.Validation;

/// <summary>
/// Revalidates the money rules on everything the server stores. The client already enforces them
/// — <c>ExpensePayload</c>'s initialiser throws — but "trust nothing from clients" (CLAUDE.md) is
/// the whole point of doing it twice. A tampered or corrupt payload gets no further than here.
/// </summary>
/// <remarks>
/// Everything is <see cref="long"/> minor units under <c>checked</c>. No <c>decimal</c>, no
/// <c>double</c>: this is the second of the two places in the system that decides whether money
/// adds up, and it has to agree with the Swift one exactly.
/// </remarks>
public static class MoneyValidator
{
    /// <summary>
    /// Validates a payload for the event types the server understands.
    /// Unknown types return <see cref="ValidationResult.Valid"/> untouched — see
    /// <c>EventValidator</c> for why that is deliberate rather than lax.
    /// </summary>
    public static ValidationResult Validate(
        string type,
        JsonElement payload,
        IReadOnlySet<Guid> knownMembers)
    {
        return type switch
        {
            EventTypes.ExpenseCreated or EventTypes.ExpenseUpdated
                => ValidateExpense(payload, knownMembers),
            EventTypes.PaymentRecorded
                => ValidatePayment(payload, knownMembers),
            _ => ValidationResult.Valid
        };
    }

    private static ValidationResult ValidateExpense(
        JsonElement payload,
        IReadOnlySet<Guid> knownMembers)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "Payload is not an object.");
        }

        if (!TryGetInt64(payload, "amountMinor", out var amountMinor))
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "amountMinor is missing or not an integer.");
        }

        if (amountMinor <= 0)
        {
            return ValidationResult.Reject(RejectionCode.InvalidAmount, $"amountMinor must be positive, got {amountMinor}.");
        }

        if (!TryGetString(payload, "currency", out var currency))
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "currency is missing.");
        }

        // M7: a group holds expenses in any currency side by side — each currency is its own
        // sub-ledger and the clients bucket by it. The server checks only that the code is a
        // currency-shaped thing; equality with the group's primary currency stopped being a rule.
        if (!IsCurrencyShaped(currency))
        {
            return ValidationResult.Reject(
                RejectionCode.MalformedPayload,
                $"'{currency}' is not a currency code (three uppercase ASCII letters).");
        }

        var payers = ReadLines(payload, "payers");
        var shares = ReadLines(payload, "shares");

        if (payers is null || shares is null)
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "payers or shares is missing or malformed.");
        }

        if (payers.Count == 0 || shares.Count == 0)
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "payers and shares must both be non-empty.");
        }

        if (HasDuplicateMembers(payers) || HasDuplicateMembers(shares))
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "A member appears twice in payers or shares.");
        }

        foreach (var line in payers)
        {
            if (line.AmountMinor <= 0)
            {
                return ValidationResult.Reject(
                    RejectionCode.InvalidAmount,
                    $"Payer {line.MemberId} paid {line.AmountMinor}; payers must be positive.");
            }
        }

        // Zero is legitimate — an exact split can leave somebody out without removing them from
        // the expense. Negative is not.
        foreach (var line in shares)
        {
            if (line.AmountMinor < 0)
            {
                return ValidationResult.Reject(
                    RejectionCode.InvalidAmount,
                    $"Share for {line.MemberId} is {line.AmountMinor}; shares must not be negative.");
            }
        }

        var unknown = FirstUnknownMember(payers, shares, knownMembers);
        if (unknown is not null)
        {
            return ValidationResult.Reject(
                RejectionCode.UnknownMember,
                $"Member {unknown} is not in this group.");
        }

        long payersTotal, sharesTotal;
        try
        {
            payersTotal = SumChecked(payers);
            sharesTotal = SumChecked(shares);
        }
        catch (OverflowException)
        {
            return ValidationResult.Reject(RejectionCode.InvalidAmount, "Amounts overflow a 64-bit integer.");
        }

        // The invariant. Everything above is a precondition for being able to state it.
        if (payersTotal != amountMinor || sharesTotal != amountMinor)
        {
            return ValidationResult.Reject(
                RejectionCode.MoneyInvariantViolated,
                $"amountMinor={amountMinor}, payers total={payersTotal}, shares total={sharesTotal}; all three must be equal.");
        }

        return ValidationResult.Valid;
    }

    private static ValidationResult ValidatePayment(
        JsonElement payload,
        IReadOnlySet<Guid> knownMembers)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "Payload is not an object.");
        }

        if (!TryGetInt64(payload, "amountMinor", out var amountMinor))
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "amountMinor is missing or not an integer.");
        }

        if (amountMinor <= 0)
        {
            return ValidationResult.Reject(RejectionCode.InvalidAmount, $"amountMinor must be positive, got {amountMinor}.");
        }

        if (!TryGetString(payload, "currency", out var currency) || !IsCurrencyShaped(currency))
        {
            return ValidationResult.Reject(
                RejectionCode.MalformedPayload,
                $"'{currency ?? "(missing)"}' is not a currency code (three uppercase ASCII letters).");
        }

        if (!TryGetGuid(payload, "fromMemberId", out var from) ||
            !TryGetGuid(payload, "toMemberId", out var to))
        {
            return ValidationResult.Reject(RejectionCode.MalformedPayload, "fromMemberId or toMemberId is missing.");
        }

        if (from == to)
        {
            return ValidationResult.Reject(RejectionCode.InvalidAmount, "A payment cannot go from a member to themselves.");
        }

        if (!knownMembers.Contains(from))
        {
            return ValidationResult.Reject(RejectionCode.UnknownMember, $"Member {from} is not in this group.");
        }

        if (!knownMembers.Contains(to))
        {
            return ValidationResult.Reject(RejectionCode.UnknownMember, $"Member {to} is not in this group.");
        }

        return ValidationResult.Valid;
    }

    // MARK: - JSON helpers

    private readonly record struct MoneyLine(Guid MemberId, long AmountMinor);

    private static List<MoneyLine>? ReadLines(JsonElement payload, string property)
    {
        if (!payload.TryGetProperty(property, out var array) || array.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        var lines = new List<MoneyLine>();
        foreach (var element in array.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.Object ||
                !TryGetGuid(element, "memberId", out var memberId) ||
                !TryGetInt64(element, "amountMinor", out var amount))
            {
                return null;
            }

            lines.Add(new MoneyLine(memberId, amount));
        }

        return lines;
    }

    private static long SumChecked(List<MoneyLine> lines)
    {
        long total = 0;
        checked
        {
            foreach (var line in lines)
            {
                total += line.AmountMinor;
            }
        }

        return total;
    }

    private static bool HasDuplicateMembers(List<MoneyLine> lines)
    {
        var seen = new HashSet<Guid>(lines.Count);
        return lines.Any(line => !seen.Add(line.MemberId));
    }

    private static Guid? FirstUnknownMember(
        List<MoneyLine> payers,
        List<MoneyLine> shares,
        IReadOnlySet<Guid> knownMembers)
    {
        foreach (var line in payers.Concat(shares))
        {
            if (!knownMembers.Contains(line.MemberId))
            {
                return line.MemberId;
            }
        }

        return null;
    }

    private static bool TryGetInt64(JsonElement element, string property, out long value)
    {
        value = 0;
        return element.TryGetProperty(property, out var found)
            && found.ValueKind == JsonValueKind.Number
            && found.TryGetInt64(out value);
    }

    /// <summary>Three ASCII uppercase letters — the same shape rule the client's decoder enforces.</summary>
    private static bool IsCurrencyShaped(string value)
    {
        if (value.Length != 3)
        {
            return false;
        }

        foreach (var c in value)
        {
            if (c is < 'A' or > 'Z')
            {
                return false;
            }
        }

        return true;
    }

    private static bool TryGetString(JsonElement element, string property, out string? value)
    {
        value = null;
        if (!element.TryGetProperty(property, out var found) || found.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = found.GetString();
        return value is not null;
    }

    private static bool TryGetGuid(JsonElement element, string property, out Guid value)
    {
        value = Guid.Empty;
        return element.TryGetProperty(property, out var found)
            && found.ValueKind == JsonValueKind.String
            && Guid.TryParse(found.GetString(), out value);
    }
}
