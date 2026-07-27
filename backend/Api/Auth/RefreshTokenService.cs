using System.Security.Cryptography;
using Kvitta.Api.Data;
using Kvitta.Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Kvitta.Api.Auth;

public sealed class RefreshTokenException(string reason) : Exception(reason);

/// <summary>Issues and rotates refresh tokens (design doc §7).</summary>
public sealed class RefreshTokenService(KvittaDbContext db, IOptions<AuthOptions> options)
{
    private readonly AuthOptions _auth = options.Value;

    /// <summary>Starts a new chain. Called once per sign-in.</summary>
    public async Task<string> IssueAsync(Guid userId, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var token = await AppendAsync(userId, Guid.NewGuid(), parentId: null, now, cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        return token;
    }

    /// <summary>
    /// Exchanges a refresh token for the next one in its chain.
    /// </summary>
    /// <remarks>
    /// The claim is a single conditional UPDATE rather than a read followed by a write. That is the
    /// whole reason this is race-free: two devices refreshing the same token at the same instant
    /// both run the statement, exactly one of them matches a row where <c>UsedAt IS NULL</c>, and
    /// the loser falls through to the reuse branch. A read-then-write would let both succeed and
    /// hand out two live chains from one token.
    /// </remarks>
    public async Task<(Guid UserId, string RefreshToken)> RotateAsync(
        string presented,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var hash = Hash(presented);

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        var claimed = await db.RefreshTokens
            .Where(token => token.TokenHash == hash
                && token.UsedAt == null
                && token.RevokedAt == null
                && token.ExpiresAt > now)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(token => token.UsedAt, now)
                    .SetProperty(token => token.RevokedReason, "rotated"),
                cancellationToken);

        if (claimed == 0)
        {
            await HandleFailedClaimAsync(hash, now, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            throw new RefreshTokenException("That refresh token is no longer valid.");
        }

        var used = await db.RefreshTokens
            .AsNoTracking()
            .SingleAsync(token => token.TokenHash == hash, cancellationToken);

        var successor = await AppendAsync(used.UserId, used.FamilyId, used.Id, now, cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return (used.UserId, successor);
    }

    /// <summary>Ends every chain this user has, for sign-out.</summary>
    public async Task RevokeAllAsync(Guid userId, DateTimeOffset now, CancellationToken cancellationToken) =>
        await db.RefreshTokens
            .Where(token => token.UserId == userId && token.RevokedAt == null)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(token => token.RevokedAt, now)
                    .SetProperty(token => token.RevokedReason, "signed_out"),
                cancellationToken);

    /// <summary>
    /// The claim matched nothing. Either the token never existed, or it is being presented twice.
    /// </summary>
    /// <remarks>
    /// A second presentation of an already-rotated token means the chain leaked, and the holder of
    /// the successor cannot be told apart from the thief. So the whole family dies — including the
    /// token currently in someone's Keychain. Logging both parties out is the correct outcome; the
    /// alternative is leaving an attacker with a working session.
    /// </remarks>
    private async Task HandleFailedClaimAsync(byte[] hash, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var existing = await db.RefreshTokens
            .AsNoTracking()
            .SingleOrDefaultAsync(token => token.TokenHash == hash, cancellationToken);

        if (existing is null || existing.UsedAt is null)
        {
            // Never existed, already revoked, or simply expired. Nothing to escalate.
            return;
        }

        await db.RefreshTokens
            .Where(token => token.FamilyId == existing.FamilyId && token.RevokedAt == null)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(token => token.RevokedAt, now)
                    .SetProperty(token => token.RevokedReason, "reuse_detected"),
                cancellationToken);
    }

    private async Task<string> AppendAsync(
        Guid userId,
        Guid familyId,
        Guid? parentId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        // Absolute, and inherited by every link in the chain. Rotating is not evidence that a
        // session deserves another full window — otherwise a token that is refreshed often enough
        // never expires at all, which is the opposite of what an expiry is for.
        var expiresAt = parentId is null
            ? now.AddDays(_auth.RefreshTokenDays)
            : await ChainExpiryAsync(familyId, cancellationToken);

        var secret = RandomNumberGenerator.GetBytes(32);

        db.RefreshTokens.Add(new RefreshTokenRecord
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TokenHash = SHA256.HashData(secret),
            FamilyId = familyId,
            ParentId = parentId,
            CreatedAt = now,
            ExpiresAt = expiresAt
        });

        return Base64UrlEncode(secret);
    }

    private Task<DateTimeOffset> ChainExpiryAsync(Guid familyId, CancellationToken cancellationToken) =>
        db.RefreshTokens
            .Where(token => token.FamilyId == familyId)
            .OrderBy(token => token.CreatedAt)
            .Select(token => token.ExpiresAt)
            .FirstAsync(cancellationToken);

    private static byte[] Hash(string presented)
    {
        try
        {
            return SHA256.HashData(Base64UrlDecode(presented));
        }
        catch (FormatException)
        {
            // A malformed token is simply not a token. Hash the raw bytes so the lookup misses
            // rather than throwing a 500 at anyone who sends rubbish.
            return SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(presented));
        }
    }

    private static string Base64UrlEncode(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded += (padded.Length % 4) switch { 2 => "==", 3 => "=", _ => "" };
        return Convert.FromBase64String(padded);
    }
}
