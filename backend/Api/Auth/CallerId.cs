namespace Kvitta.Api.Auth;

/// <summary>
/// The authenticated caller, from the access token this server signed.
/// </summary>
/// <remarks>
/// One implementation, for the same reason <see cref="Data.Membership"/> is one implementation:
/// this used to read a trusted header, and a rule about who someone is should not have copies that
/// can drift apart.
///
/// Reading <c>sub</c> literally only works because <c>MapInboundClaims</c> is off in
/// <c>Program.cs</c>. With the default on, the bearer handler renames it to
/// <c>ClaimTypes.NameIdentifier</c> and this returns false for every authenticated request.
/// </remarks>
public static class CallerId
{
    public static bool TryRead(HttpContext http, out Guid userId)
    {
        userId = Guid.Empty;
        var subject = http.User.FindFirst("sub")?.Value;
        return subject is not null && Guid.TryParse(subject, out userId);
    }
}
