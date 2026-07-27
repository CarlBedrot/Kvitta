using Microsoft.Extensions.Options;

namespace Kvitta.Api.Tests;

/// <summary>
/// The signing key has no default and no committed value anywhere, so the only two outcomes are
/// "configured properly" and "does not start".
/// </summary>
/// <remarks>
/// A fallback key would be worse than no key: it would boot happily in production signing tokens
/// with a value that is in the repository and therefore known to everyone. Refusing to start is the
/// loud failure, and it doubles as the reason there is nothing here for a secret scanner to find.
/// </remarks>
[Collection(nameof(KvittaApiCollection))]
public sealed class AuthConfigurationTests(KvittaApiFixture fixture)
{
    [Fact]
    public void The_host_refuses_to_start_without_a_signing_key()
    {
        var failure = Assert.Throws<OptionsValidationException>(() =>
            fixture.CreateClient(new Dictionary<string, string?> { ["Auth:SigningKey"] = null }));

        Assert.Contains(nameof(Kvitta.Api.Options.AuthOptions.SigningKey), failure.Message);
    }

    [Fact]
    public void The_host_refuses_to_start_with_a_signing_key_too_short_for_HS256()
    {
        // Anything under 32 bytes is a smaller key than the algorithm's own output, which makes
        // brute force meaningfully cheaper than it should be.
        var failure = Assert.Throws<OptionsValidationException>(() =>
            fixture.CreateClient(new Dictionary<string, string?> { ["Auth:SigningKey"] = "too-short" }));

        Assert.Contains(nameof(Kvitta.Api.Options.AuthOptions.SigningKey), failure.Message);
    }

    [Fact]
    public void A_properly_configured_host_starts()
    {
        // The control. Without it the two tests above would pass just as happily if the host
        // refused to start for some entirely unrelated reason.
        var client = fixture.CreateClient(new Dictionary<string, string?>());

        Assert.NotNull(client);
    }
}
