namespace Kvitta.Api.Validation;

/// <summary>
/// Why an event was refused. Stable strings, because the client stores them against the outbox
/// row and shows them to a human — design doc §7 requires rejected events to be surfaced
/// "rather than silently dropping them".
/// </summary>
public static class RejectionCode
{
    public const string MalformedEnvelope = "malformed_envelope";
    public const string GroupMismatch = "group_mismatch";
    public const string NotAMember = "not_a_member";
    public const string GroupNotBootstrapped = "group_not_bootstrapped";
    public const string MoneyInvariantViolated = "money_invariant_violated";
    public const string InvalidAmount = "invalid_amount";
    public const string UnknownMember = "unknown_member";
    // Retired in M7: a group holds any mix of currencies, each its own sub-ledger. The constant
    // stays because rejected events recorded before M7 still carry it and clients still map it.
    public const string CurrencyMismatch = "currency_mismatch";
    public const string MalformedPayload = "malformed_payload";
    public const string PayloadTooLarge = "payload_too_large";

    /// <summary>The envelope claims an author who is not the caller.</summary>
    public const string AuthorMismatch = "author_mismatch";

    /// <summary>A MemberAdded tried to attach the group member to somebody other than the caller.</summary>
    public const string UnauthorizedLink = "unauthorized_link";
}

/// <summary>The outcome of validating one event. A rejection carries a code the client can act on.</summary>
public readonly record struct ValidationResult(bool IsValid, string? Code, string? Reason)
{
    public static ValidationResult Valid { get; } = new(true, null, null);

    public static ValidationResult Reject(string code, string reason) => new(false, code, reason);
}
