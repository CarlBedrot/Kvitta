using System.ComponentModel.DataAnnotations;

namespace Kvitta.Api.Options;

/// <summary>
/// Bound from configuration through DI. CLAUDE.md forbids reaching for
/// <c>Environment.GetEnvironmentVariable</c> anywhere in this codebase.
/// </summary>
public sealed class DatabaseOptions
{
    public const string SectionName = "Database";

    [Required(AllowEmptyStrings = false)]
    public string ConnectionString { get; init; } = "";

    /// <summary>Run EF migrations at startup. Convenient locally; a deploy step in production.</summary>
    public bool MigrateOnStartup { get; init; }
}

public sealed class SyncOptions
{
    public const string SectionName = "Sync";

    /// <summary>Largest page a pull will return, whatever the client asks for.</summary>
    [Range(1, 5000)]
    public int MaxPullLimit { get; init; } = 500;

    /// <summary>Largest batch a single push may carry.</summary>
    [Range(1, 5000)]
    public int MaxPushBatchSize { get; init; } = 500;

    /// <summary>Cap on a single event's payload, so one client cannot post a novel.</summary>
    [Range(1024, 4 * 1024 * 1024)]
    public int MaxPayloadBytes { get; init; } = 256 * 1024;

    /// <summary>
    /// Clients below this build get 426 Upgrade Required. Design doc §9: "Build this in v1, you
    /// will want it exactly once and it will save you." Zero disables the check.
    /// </summary>
    [Range(0, int.MaxValue)]
    public int MinimumClientBuild { get; init; }
}

/// <summary>
/// Crash and error reporting. Off unless a DSN is configured, which is the whole of the switch.
/// </summary>
/// <remarks>
/// The DSN is not committed anywhere, for the same reason the signing key is not: it is a write
/// credential for somebody else's service. Locally it comes from <c>dotnet user-secrets</c>, in a
/// deploy from the host's environment. Unlike the signing key its absence is not fatal — a server
/// with no error reporting still works, it just tells nobody when it breaks.
/// </remarks>
public sealed class ObservabilityOptions
{
    public const string SectionName = "Observability";

    /// <summary>Empty means Sentry is never initialised at all.</summary>
    public string SentryDsn { get; init; } = "";

    /// <summary>
    /// Fraction of requests traced for performance. Zero by default: this is a friend group's
    /// API on a free plan, and a full trace of every push would spend the quota on nothing.
    /// </summary>
    [Range(0.0, 1.0)]
    public double TracesSampleRate { get; init; }

    /// <summary>
    /// Tags every event, so a laptop's stack trace never gets mistaken for a live one. Falls back
    /// to the hosting environment name when unset.
    /// </summary>
    public string? Environment { get; init; }
}

/// <summary>
/// Sign in with Apple, and the tokens this server issues off the back of it (design doc §7).
/// </summary>
public sealed class AuthOptions
{
    public const string SectionName = "Auth";

    /// <summary>
    /// HS256 key for the access tokens this server signs.
    /// </summary>
    /// <remarks>
    /// Deliberately has no default and no value in any committed appsettings file: a checked-in
    /// signing key is itself a backdoor, and the host refusing to start is a far better failure
    /// than one that boots with a key everybody knows. Locally it comes from
    /// <c>dotnet user-secrets</c>; in tests from the fixture's in-memory configuration.
    /// 32 bytes is the minimum HS256 should ever be given.
    /// </remarks>
    [Required(AllowEmptyStrings = false)]
    [MinLength(32)]
    public string SigningKey { get; init; } = "";

    [Required(AllowEmptyStrings = false)]
    public string Issuer { get; init; } = "https://kvitta.se";

    [Required(AllowEmptyStrings = false)]
    public string Audience { get; init; } = "se.kvitta.app";

    /// <summary>
    /// Sixty minutes, not fifteen. Sync runs on foreground and a debounced push, so a short
    /// lifetime would put a refresh round-trip in front of nearly every sync — and every refresh is
    /// a chance to trip refresh-token reuse detection.
    /// </summary>
    [Range(1, 1440)]
    public int AccessTokenMinutes { get; init; } = 60;

    /// <summary>Absolute, and not extended by rotation.</summary>
    [Range(1, 365)]
    public int RefreshTokenDays { get; init; } = 60;

    /// <summary>The audience Apple puts in the identity token: our bundle id.</summary>
    [Required(AllowEmptyStrings = false)]
    public string AppleBundleId { get; init; } = "se.kvitta.app";

    [Required(AllowEmptyStrings = false)]
    public string AppleIssuer { get; init; } = "https://appleid.apple.com";

    /// <summary>
    /// Apple's OpenID discovery document. Preferred over pointing straight at the JWKS endpoint
    /// because the standard retriever handles key rollover and caching for us — and Apple does
    /// rotate its signing keys.
    /// </summary>
    [Required(AllowEmptyStrings = false)]
    public string AppleMetadataAddress { get; init; } = "https://appleid.apple.com/.well-known/openid-configuration";

    /// <summary>How long an invite link stays good for. Design doc §7: tokens expire.</summary>
    [Range(1, 365)]
    public int InviteLifetimeDays { get; init; } = 14;

    /// <summary>Sign-in and refresh attempts allowed per caller per minute.</summary>
    [Range(1, 100_000)]
    public int AuthAttemptsPerMinute { get; init; } = 20;

    /// <summary>
    /// Enables <c>POST /api/v1/auth/dev</c>, which mints a token without an Apple round-trip.
    /// Only honoured in the Development environment, and <see cref="AuthOptionsGuard"/> refuses to
    /// let the host start anywhere else with it on.
    /// </summary>
    public bool AllowDevTokens { get; init; }
}
