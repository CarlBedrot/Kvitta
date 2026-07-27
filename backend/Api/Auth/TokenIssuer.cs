using System.Text;
using Kvitta.Api.Options;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace Kvitta.Api.Auth;

public readonly record struct AccessToken(string Value, DateTimeOffset ExpiresAt)
{
    public int ExpiresInSeconds(DateTimeOffset now) =>
        (int)Math.Max(0, (ExpiresAt - now).TotalSeconds);
}

/// <summary>
/// Signs this server's own access tokens. Apple proves who you are once; after that every request
/// carries one of these instead (design doc §7).
/// </summary>
/// <remarks>
/// The subject is our own user id, never Apple's <c>sub</c>. Apple's identifier is an
/// implementation detail of one login method, and putting it on the wire would leak it into every
/// request and make a second login method a breaking change.
/// </remarks>
public sealed class TokenIssuer(IOptions<AuthOptions> options)
{
    private readonly AuthOptions _auth = options.Value;
    private readonly JsonWebTokenHandler _handler = new();

    public AccessToken Issue(Guid userId, DateTimeOffset now)
    {
        var expiresAt = now.AddMinutes(_auth.AccessTokenMinutes);

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = _auth.Issuer,
            Audience = _auth.Audience,
            IssuedAt = now.UtcDateTime,
            NotBefore = now.UtcDateTime,
            Expires = expiresAt.UtcDateTime,
            Claims = new Dictionary<string, object> { ["sub"] = userId.ToString() },
            SigningCredentials = new SigningCredentials(SigningKey(_auth), SecurityAlgorithms.HmacSha256)
        };

        return new AccessToken(_handler.CreateToken(descriptor), expiresAt);
    }

    public static SymmetricSecurityKey SigningKey(AuthOptions auth) =>
        new(Encoding.UTF8.GetBytes(auth.SigningKey));
}
