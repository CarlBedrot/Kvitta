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
