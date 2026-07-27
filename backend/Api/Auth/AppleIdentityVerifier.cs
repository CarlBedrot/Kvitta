using System.Security.Cryptography;
using System.Text;
using Kvitta.Api.Options;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace Kvitta.Api.Auth;

/// <summary>Who Apple says this is. <c>Subject</c> is stable per app, per Apple account.</summary>
public readonly record struct AppleIdentity(string Subject, string? Email);

public sealed class AppleIdentityException(string reason) : Exception(reason);

/// <summary>
/// Verifies the identity token an iOS client gets back from Sign in with Apple (design doc §7).
/// </summary>
/// <remarks>
/// Concrete on purpose, with only the key source injected. An interface here would mean the
/// integration tests exercised a stand-in and never ran signature verification, issuer, audience,
/// expiry or algorithm checks — which are the only parts of this that can be wrong. Tests instead
/// hand it a <c>StaticConfigurationManager</c> holding a locally generated RSA public key and sign
/// tokens with the private half, so the code under test is the code that ships.
/// </remarks>
public sealed class AppleIdentityVerifier(
    IConfigurationManager<OpenIdConnectConfiguration> metadata,
    IOptions<AuthOptions> options)
{
    private readonly AuthOptions _auth = options.Value;
    private readonly JsonWebTokenHandler _handler = new();

    public async Task<AppleIdentity> VerifyAsync(
        string identityToken,
        string rawNonce,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(identityToken))
        {
            throw new AppleIdentityException("No identity token was supplied.");
        }

        var configuration = await metadata.GetConfigurationAsync(cancellationToken);

        var parameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = _auth.AppleIssuer,
            // Apple puts our bundle id here. Skipping it would let an identity token minted for a
            // completely different app be replayed against this server.
            ValidateAudience = true,
            ValidAudience = _auth.AppleBundleId,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = configuration.SigningKeys,
            // Pinned. Apple signs with RS256, and leaving this open is how "alg": "none" and
            // HMAC-with-the-public-key attacks get in.
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            ClockSkew = TimeSpan.FromSeconds(30)
        };

        var result = await _handler.ValidateTokenAsync(identityToken, parameters);
        if (!result.IsValid)
        {
            throw new AppleIdentityException(result.Exception?.Message ?? "The identity token did not validate.");
        }

        var token = (JsonWebToken)result.SecurityToken;
        VerifyNonce(token, rawNonce);

        var subject = token.Subject;
        if (string.IsNullOrWhiteSpace(subject))
        {
            throw new AppleIdentityException("The identity token carried no subject.");
        }

        token.TryGetClaim("email", out var email);
        return new AppleIdentity(subject, email?.Value);
    }

    /// <summary>
    /// Ties this token to the sign-in attempt that asked for it.
    /// </summary>
    /// <remarks>
    /// The client generates a random nonce, hands Apple its SHA-256, and sends us the raw value.
    /// Apple echoes the hash back in the token, so a token captured from one sign-in cannot be
    /// replayed into another — the attacker would have to produce the pre-image.
    ///
    /// Worth being honest about the limit: the nonce is chosen by the client, not issued by this
    /// server, so this defeats replay of a leaked token and not an attacker sitting in the middle
    /// of a live sign-in. Server-issued nonces are the upgrade if that ever matters.
    /// </remarks>
    private static void VerifyNonce(JsonWebToken token, string rawNonce)
    {
        if (!token.TryGetClaim("nonce", out var claim) || string.IsNullOrEmpty(claim.Value))
        {
            throw new AppleIdentityException("The identity token carried no nonce.");
        }

        var expected = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawNonce)))
            .ToLowerInvariant();

        // Fixed-time: the comparand is derived from attacker-supplied input, so an early-exit
        // compare leaks how much of the hash matched.
        var supplied = Encoding.UTF8.GetBytes(claim.Value);
        if (!CryptographicOperations.FixedTimeEquals(supplied, Encoding.UTF8.GetBytes(expected)))
        {
            throw new AppleIdentityException("The identity token's nonce did not match this sign-in.");
        }
    }
}
