using Kvitta.Api.Options;

namespace Kvitta.Api.Tests;

/// <summary>
/// The server's logging policy is "codes and ids only, no names, no amounts" (CLAUDE.md). Error
/// reporting is a second channel out of the same process, and these tests are what stop it from
/// quietly becoming a more generous one.
/// </summary>
/// <remarks>
/// <see cref="SentryScrubbing.Scrub"/> is a pure function precisely so this can be asserted without
/// a DSN, a network, or an initialised SDK.
/// </remarks>
public sealed class SentryScrubbingTests
{
    [Theory]
    [InlineData("Authorization")]
    [InlineData("Cookie")]
    [InlineData("Set-Cookie")]
    public void Credential_bearing_headers_never_leave(string header)
    {
        var sentryEvent = new SentryEvent();
        sentryEvent.Request.Headers[header] = "Bearer eyJhbGciOiJIUzI1NiJ9.the-real-thing";

        SentryScrubbing.Scrub(sentryEvent);

        Assert.False(sentryEvent.Request.Headers.ContainsKey(header));
    }

    [Fact]
    public void Header_removal_is_case_insensitive_about_nothing_it_does_not_know()
    {
        // Guards the shape of the list rather than one entry: adding a header to
        // SensitiveHeaders must be all it takes, with no second place to remember.
        var sentryEvent = new SentryEvent();

        foreach (var header in SentryScrubbing.SensitiveHeaders)
        {
            sentryEvent.Request.Headers[header] = "secret";
        }

        SentryScrubbing.Scrub(sentryEvent);

        Assert.Empty(sentryEvent.Request.Headers);
    }

    [Fact]
    public void The_callers_ip_address_is_dropped()
    {
        var sentryEvent = new SentryEvent();
        sentryEvent.User.IpAddress = "192.168.0.155";
        sentryEvent.Request.Env["REMOTE_ADDR"] = "192.168.0.155";

        SentryScrubbing.Scrub(sentryEvent);

        Assert.Null(sentryEvent.User.IpAddress);
        Assert.False(sentryEvent.Request.Env.ContainsKey("REMOTE_ADDR"));
    }

    [Fact]
    public void The_machine_name_is_dropped()
    {
        // On a deploy this is a container id and harmless. On the laptop the server actually runs
        // on today it is the owner's name, which is not ours to send anywhere.
        var sentryEvent = new SentryEvent { ServerName = "Carls-MacBook-Pro.local" };

        SentryScrubbing.Scrub(sentryEvent);

        Assert.Null(sentryEvent.ServerName);
    }

    [Fact]
    public void Ids_and_rejection_codes_survive()
    {
        // The other half of the contract. Scrubbing that took the ids too would leave reports
        // nobody can act on, which is the failure mode that makes people switch reporting off.
        var groupId = Guid.NewGuid();
        var sentryEvent = new SentryEvent();
        sentryEvent.Request.Url = $"http://localhost:5142/api/v1/groups/{groupId}/events";
        sentryEvent.SetTag("rejection_code", "money_invariant_violated");

        SentryScrubbing.Scrub(sentryEvent);

        Assert.Contains(groupId.ToString(), sentryEvent.Request.Url);
        Assert.Equal("money_invariant_violated", sentryEvent.Tags["rejection_code"]);
    }

    [Fact]
    public void An_event_with_nothing_to_scrub_passes_through_unharmed()
    {
        var sentryEvent = new SentryEvent();

        var result = SentryScrubbing.Scrub(sentryEvent);

        Assert.Same(sentryEvent, result);
    }
}
