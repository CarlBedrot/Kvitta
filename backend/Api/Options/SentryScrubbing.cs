namespace Kvitta.Api.Options;

/// <summary>
/// The last thing that touches an error before it leaves this machine.
/// </summary>
/// <remarks>
/// The server already logs "codes and ids only, no names, no amounts" (CLAUDE.md), and an error
/// reporter that quietly ships more than the logs do would undo that decision without anyone
/// choosing it. So the same rule is applied here, in one place, as a pure function — which is also
/// what makes it testable without a live Sentry.
///
/// What this removes, and why each one is not covered by <c>SendDefaultPii = false</c>:
/// <list type="bullet">
/// <item><c>Authorization</c> — a live access token. The single worst thing that could leave here,
/// and the one an exception in a request handler is most likely to be carrying.</item>
/// <item><c>Cookie</c> — nothing sets one today, which is exactly why it would go unnoticed if
/// something started.</item>
/// <item><c>ServerName</c> — defaults to the machine's hostname. On a deploy that is a container
/// id; on the laptop this actually runs on it is Carl's name.</item>
/// </list>
///
/// What it deliberately does <b>not</b> attempt: rewriting exception messages. Nothing in this
/// codebase puts an amount or a member's name into one — money never reaches an exception path,
/// and Npgsql's parameter values stay out of errors unless <c>IncludeErrorDetail</c> is switched
/// on, which it is not. A regex sweep over free text would catch the cases we already thought of
/// and give false confidence about the ones we did not, which is worse than knowing the boundary.
///
/// Group ids, user ids and rejection codes are kept on purpose. They are the same identifiers the
/// structured logs carry, they are what makes a report actionable, and none of them says who
/// anybody is or how much anything cost.
/// </remarks>
public static class SentryScrubbing
{
    /// <summary>Header names dropped from every outgoing event.</summary>
    public static readonly string[] SensitiveHeaders = ["Authorization", "Cookie", "Set-Cookie"];

    /// <summary>
    /// Strips credentials and host identity from an event, in place, and hands it back.
    /// </summary>
    public static SentryEvent Scrub(SentryEvent sentryEvent)
    {
        foreach (var header in SensitiveHeaders)
        {
            sentryEvent.Request.Headers.Remove(header);
        }

        // Redundant with SendDefaultPii = false today. Kept because the cost is one line and the
        // failure mode of the option being flipped on for a debugging session is a silent one.
        sentryEvent.Request.Env.Remove("REMOTE_ADDR");
        sentryEvent.User.IpAddress = null;

        sentryEvent.ServerName = null;

        return sentryEvent;
    }
}
