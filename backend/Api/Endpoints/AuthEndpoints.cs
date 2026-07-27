using Kvitta.Api.Auth;
using Kvitta.Api.Data;
using Kvitta.Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Kvitta.Api.Endpoints;

public sealed record AppleSignInRequest(string IdentityToken, string Nonce, string? DisplayName);

public sealed record RefreshRequest(string RefreshToken);

public sealed record DevSignInRequest(Guid? UserId, string? DisplayName);

public sealed record SessionResponse(Guid UserId, string AccessToken, int ExpiresIn, string RefreshToken);

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder routes, IHostEnvironment environment)
    {
        var group = routes.MapGroup("/api/v1/auth").RequireRateLimiting("auth");

        group.MapPost("/apple", SignInWithAppleAsync);
        group.MapPost("/refresh", RefreshAsync);

        // The development shortcut is not mapped unless it is switched on, so with the option off
        // it answers 404 rather than 401 — there is no code path to reach at all, which is a
        // stronger guarantee than any check inside a handler.
        //
        // The environment half of this condition is belt to AuthOptionsGuard's braces: that guard
        // runs during startup and so refuses to boot a non-Development host with the option on,
        // which means this line never actually gets to be the thing that saves us. Both stay,
        // because the cost is a boolean and the failure mode is handing out accounts.
        var options = routes.ServiceProvider.GetRequiredService<IOptions<AuthOptions>>().Value;
        if (environment.IsDevelopment() && options.AllowDevTokens)
        {
            group.MapPost("/dev", DevSignInAsync);
        }
    }

    /// <summary>
    /// Exchanges an Apple identity token for a session (design doc §7).
    /// </summary>
    /// <remarks>
    /// The user id is minted here and nowhere else. An earlier draft let the client propose one so
    /// that data written before signing in would keep matching; that was an account-takeover
    /// primitive, because the id it wanted to propose is stamped on every event's authorId and sits
    /// in MemberAdded.linkedUserId — meaning every co-member's device already knows it.
    /// </remarks>
    private static async Task<IResult> SignInWithAppleAsync(
        AppleSignInRequest request,
        AppleIdentityVerifier verifier,
        KvittaDbContext db,
        TokenIssuer issuer,
        RefreshTokenService refreshTokens,
        TimeProvider time,
        CancellationToken cancellationToken)
    {
        AppleIdentity identity;
        try
        {
            identity = await verifier.VerifyAsync(request.IdentityToken, request.Nonce ?? "", cancellationToken);
        }
        catch (AppleIdentityException exception)
        {
            return Results.Problem(
                title: "Sign in failed",
                detail: exception.Message,
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var now = time.GetUtcNow();
        var user = await db.Users.SingleOrDefaultAsync(
            candidate => candidate.AppleSub == identity.Subject,
            cancellationToken);

        if (user is null)
        {
            user = new UserRecord
            {
                Id = Guid.NewGuid(),
                AppleSub = identity.Subject,
                DisplayName = request.DisplayName,
                CreatedAt = now
            };
            db.Users.Add(user);
            await db.SaveChangesAsync(cancellationToken);
        }
        else if (user.DisplayName is null && request.DisplayName is { Length: > 0 })
        {
            // Apple only hands over a name on the very first authorization, so if we ever miss it
            // we never get another chance.
            user.DisplayName = request.DisplayName;
            await db.SaveChangesAsync(cancellationToken);
        }

        return Results.Ok(await IssueSessionAsync(user.Id, issuer, refreshTokens, now, cancellationToken));
    }

    private static async Task<IResult> RefreshAsync(
        RefreshRequest request,
        RefreshTokenService refreshTokens,
        TokenIssuer issuer,
        TimeProvider time,
        CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();

        try
        {
            var (userId, refreshToken) = await refreshTokens.RotateAsync(
                request.RefreshToken ?? "",
                now,
                cancellationToken);

            var access = issuer.Issue(userId, now);
            return Results.Ok(new SessionResponse(
                userId,
                access.Value,
                access.ExpiresInSeconds(now),
                refreshToken));
        }
        catch (RefreshTokenException exception)
        {
            return Results.Problem(
                title: "Refresh failed",
                detail: exception.Message,
                statusCode: StatusCodes.Status401Unauthorized);
        }
    }

    /// <summary>
    /// Signs in without Apple. Only ever reachable in Development (see <see cref="MapAuthEndpoints"/>).
    /// </summary>
    /// <remarks>
    /// Exists because Sign in with Apple needs a paid Apple Developer team to add the entitlement,
    /// and without one the simulator cannot complete a real sign-in — so this is the only way to
    /// exercise the authenticated app locally. It refuses any user that has an Apple identity, so
    /// even in Development it cannot be pointed at a real account.
    /// </remarks>
    private static async Task<IResult> DevSignInAsync(
        DevSignInRequest request,
        KvittaDbContext db,
        TokenIssuer issuer,
        RefreshTokenService refreshTokens,
        TimeProvider time,
        CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var userId = request.UserId ?? Guid.NewGuid();

        var user = await db.Users.SingleOrDefaultAsync(
            candidate => candidate.Id == userId,
            cancellationToken);

        if (user is null)
        {
            user = new UserRecord
            {
                Id = userId,
                AppleSub = null,
                DisplayName = request.DisplayName,
                CreatedAt = now
            };
            db.Users.Add(user);
            await db.SaveChangesAsync(cancellationToken);
        }
        else if (user.AppleSub is not null)
        {
            return Results.Problem(
                title: "Not a development account",
                detail: "That user signed in with Apple and cannot be impersonated.",
                statusCode: StatusCodes.Status403Forbidden);
        }

        return Results.Ok(await IssueSessionAsync(user.Id, issuer, refreshTokens, now, cancellationToken));
    }

    private static async Task<SessionResponse> IssueSessionAsync(
        Guid userId,
        TokenIssuer issuer,
        RefreshTokenService refreshTokens,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var access = issuer.Issue(userId, now);
        var refresh = await refreshTokens.IssueAsync(userId, now, cancellationToken);

        return new SessionResponse(userId, access.Value, access.ExpiresInSeconds(now), refresh);
    }
}
