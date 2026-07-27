using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace Kvitta.Api.Tests;

/// <summary>
/// Access tokens minted in-process, signed with the same key the test host validates against.
/// </summary>
/// <remarks>
/// Deliberately not <c>POST /api/v1/auth/dev</c>. That endpoint is only mapped in the Development
/// environment and this host runs as Testing — and widening the dev shortcut so tests could reach
/// it is exactly how a sign-in bypass ends up somewhere it should never be. Minting here keeps the
/// shortcut irrelevant to the suite.
///
/// <c>AuthEndpointTests.The_access_token_it_returns_is_accepted_by_the_event_routes</c> is what
/// stops this drifting from the real issuer: it takes a token from <c>/auth/apple</c> and spends it
/// on a real endpoint, so if the issuer, audience or algorithm here stopped matching the app's,
/// that test fails.
/// </remarks>
public static class TestTokens
{
    public static string AccessTokenFor(
        Guid userId,
        DateTimeOffset? expires = null,
        string? issuer = null,
        string? audience = null,
        SigningCredentials? credentials = null)
    {
        var now = DateTimeOffset.UtcNow;

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = issuer ?? KvittaApiFixture.Issuer,
            Audience = audience ?? KvittaApiFixture.Audience,
            IssuedAt = now.UtcDateTime,
            NotBefore = now.AddMinutes(-1).UtcDateTime,
            Expires = (expires ?? now.AddMinutes(30)).UtcDateTime,
            Claims = new Dictionary<string, object> { ["sub"] = userId.ToString() },
            SigningCredentials = credentials ?? Credentials(KvittaApiFixture.SigningKey)
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }

    public static SigningCredentials Credentials(string key) =>
        new(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256);

    /// <summary>A correctly formed token signed with a key this server has never seen.</summary>
    public static SigningCredentials WrongKey() =>
        Credentials("a-completely-different-signing-key-32-bytes");
}
