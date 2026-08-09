using System.Net;

namespace Kvitta.Api.Options;

/// <summary>
/// Works out whether the development sign-in shortcut is reachable from other machines.
/// </summary>
/// <remarks>
/// <see cref="AuthOptionsGuard"/> stops the shortcut existing outside Development. This one covers
/// the case that guard deliberately allows: Development, on a laptop, bound to the LAN so a
/// sideloaded build on a friend's phone can reach it. That is a supported setup — it is how the
/// trial works at all — but the endpoint mints a token for any user id with no credential, so
/// while it is exposed anyone on the same Wi-Fi can impersonate any user and read a group's whole
/// money history. Fine on a home network, not fine on café or office Wi-Fi.
///
/// The danger is that none of that is visible: the bind address lives in launchSettings.json and
/// the flag lives in appsettings.Development.json, so nothing at the moment of running the server
/// says the two have combined. Hence a warning at boot rather than documentation nobody re-reads.
/// It deliberately does not refuse to start: the exposed mode is the one the trial needs.
/// </remarks>
public static class DevTokenExposure
{
    /// <summary>
    /// The addresses that make the dev endpoint reachable from another machine, or empty when the
    /// shortcut is off or the server only listens on loopback.
    /// </summary>
    public static IReadOnlyList<string> ReachableAddresses(
        bool allowDevTokens,
        IEnumerable<string> serverAddresses)
    {
        if (!allowDevTokens)
        {
            return [];
        }

        return serverAddresses.Where(ReachableFromOtherMachines).ToList();
    }

    private static bool ReachableFromOtherMachines(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri))
        {
            return false;
        }

        // Uri keeps the brackets on an IPv6 literal, and IPAddress.TryParse will not take them.
        var host = uri.Host.Trim('[', ']');

        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        // 0.0.0.0 and :: are the wildcards that mean "every interface", and neither counts as
        // loopback — which is the whole point: they are exactly the exposed case.
        return !IPAddress.TryParse(host, out var ip) || !IPAddress.IsLoopback(ip);
    }
}
