using Kvitta.Api.Options;

namespace Kvitta.Api.Tests;

/// <summary>
/// The dev sign-in shortcut is allowed to be reachable from the LAN — the friend-phone trial needs
/// exactly that — so the safeguard is that it says so at boot rather than that it refuses.
/// </summary>
/// <remarks>
/// The bug being guarded against is silence, not exposure: the bind address lives in
/// launchSettings.json and the flag lives in appsettings.Development.json, so nothing at the moment
/// of running the server tells you the two have combined into an endpoint that mints a token for
/// any user id to anyone on the Wi-Fi.
/// </remarks>
public sealed class DevTokenExposureTests
{
    [Theory]
    [InlineData("http://0.0.0.0:5142")]        // the wildcard the trial needs
    [InlineData("http://[::]:5142")]           // its IPv6 twin
    [InlineData("http://192.168.0.155:5142")]  // an explicit LAN address
    public void An_address_other_machines_can_reach_is_reported(string address)
    {
        var exposed = DevTokenExposure.ReachableAddresses(allowDevTokens: true, [address]);

        Assert.Equal([address], exposed);
    }

    [Theory]
    [InlineData("http://localhost:5142")]
    [InlineData("http://127.0.0.1:5142")]
    [InlineData("http://[::1]:5142")]
    public void Loopback_is_not_reported(string address)
    {
        Assert.Empty(DevTokenExposure.ReachableAddresses(allowDevTokens: true, [address]));
    }

    [Fact]
    public void Nothing_is_reported_when_the_shortcut_is_off()
    {
        // The exposed bind address is not itself the problem — a deployed host binds the world and
        // is fine, because there is no endpoint handing out accounts behind it.
        Assert.Empty(DevTokenExposure.ReachableAddresses(
            allowDevTokens: false, ["http://0.0.0.0:5142"]));
    }

    [Fact]
    public void Only_the_reachable_half_of_a_mixed_binding_is_reported()
    {
        // The https launch profile binds both, and the warning should name the one that matters
        // rather than the whole list.
        var exposed = DevTokenExposure.ReachableAddresses(
            allowDevTokens: true, ["https://localhost:7142", "http://0.0.0.0:5142"]);

        Assert.Equal(["http://0.0.0.0:5142"], exposed);
    }
}
