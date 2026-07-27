using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace Kvitta.Api.Tests;

/// <summary>
/// Stands in for Apple's signing keys, so the verifier can be tested without a network call.
/// </summary>
/// <remarks>
/// Only the key source is substituted. Everything the verifier actually does — RS256 signature
/// checking, issuer, audience, expiry, algorithm pinning, nonce comparison — runs for real against
/// tokens signed with a genuine RSA private key. Faking the verifier itself would have left every
/// one of those untested, which is the whole reason Sign in with Apple is worth testing at all.
/// </remarks>
public static class AppleTestKeys
{
    public const string Issuer = "https://appleid.apple.com";

    private static readonly RSA Rsa = RSA.Create(2048);

    public static readonly RsaSecurityKey SigningKey = new(Rsa) { KeyId = "kvitta-test-key" };

    public static IConfigurationManager<OpenIdConnectConfiguration> ConfigurationManager()
    {
        var configuration = new OpenIdConnectConfiguration { Issuer = Issuer };
        configuration.SigningKeys.Add(SigningKey);
        return new StaticConfigurationManager<OpenIdConnectConfiguration>(configuration);
    }

    /// <summary>Apple hashes the nonce before echoing it back; the raw value is what we send.</summary>
    public static string HashedNonce(string rawNonce) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawNonce))).ToLowerInvariant();

    /// <summary>
    /// An identity token shaped like Apple's. Every field is overridable so the tests can forge the
    /// specific kinds of wrong that matter.
    /// </summary>
    public static string IdentityToken(
        string subject = "000123.abcdef.4711",
        string rawNonce = "test-nonce",
        string? nonceClaim = null,
        string audience = "se.kvitta.app",
        string issuer = Issuer,
        string? email = "carl@example.com",
        DateTimeOffset? expires = null,
        SigningCredentials? credentials = null)
    {
        var now = DateTimeOffset.UtcNow;

        var claims = new Dictionary<string, object>
        {
            ["sub"] = subject,
            ["nonce"] = nonceClaim ?? HashedNonce(rawNonce)
        };

        if (email is not null)
        {
            claims["email"] = email;
        }

        var descriptor = new SecurityTokenDescriptor
        {
            Issuer = issuer,
            Audience = audience,
            IssuedAt = now.UtcDateTime,
            NotBefore = now.AddMinutes(-1).UtcDateTime,
            Expires = (expires ?? now.AddMinutes(10)).UtcDateTime,
            Claims = claims,
            SigningCredentials = credentials
                ?? new SigningCredentials(SigningKey, SecurityAlgorithms.RsaSha256)
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }

    /// <summary>A different, equally valid RSA key — for "correctly signed, by the wrong party".</summary>
    public static SigningCredentials ImposterCredentials() =>
        new(new RsaSecurityKey(RSA.Create(2048)) { KeyId = "imposter" }, SecurityAlgorithms.RsaSha256);

    /// <summary>
    /// HS256 signed with the server's own key — the algorithm-confusion shape. If the verifier did
    /// not pin RS256, a token signed with a symmetric key it already trusts would sail through.
    /// </summary>
    public static SigningCredentials AlgorithmConfusionCredentials() =>
        new(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(KvittaApiFixture.SigningKey)),
            SecurityAlgorithms.HmacSha256);
}
