using Microsoft.Extensions.Options;

namespace Kvitta.Api.Options;

/// <summary>
/// Refuses to let the host start with the development sign-in shortcut enabled anywhere but
/// Development, unless a trial key stands in front of it.
/// </summary>
/// <remarks>
/// The dev endpoint mints an access token for any user id with no Apple round-trip, so switching it
/// on in a deployed environment would hand out accounts to anyone who can reach the port. With
/// <see cref="AuthOptions.TrialKey"/> set the endpoint demands that key on every call, which is
/// enough to host the friend-phone trial outside the home network until Sign in with Apple exists.
/// Without one the route is already never mapped outside Development, which is the guard that
/// actually stops it; this one exists so a misconfiguration is a loud crash at boot rather than a
/// quiet setting nobody reads.
///
/// Note that "not Development" includes the Testing environment the integration tests run in. That
/// is deliberate: tests mint their own tokens in-process from the configured signing key and never
/// call the dev endpoint, so there is no reason to widen this — and widening it is exactly how the
/// shortcut would end up reachable in production.
/// </remarks>
public sealed class AuthOptionsGuard(IHostEnvironment environment) : IValidateOptions<AuthOptions>
{
    public ValidateOptionsResult Validate(string? name, AuthOptions options)
    {
        if (options.RequiresTrialKey && options.TrialKey.Length < AuthOptions.MinimumTrialKeyLength)
        {
            return ValidateOptionsResult.Fail(
                $"{AuthOptions.SectionName}:{nameof(AuthOptions.TrialKey)} must be at least "
                + $"{AuthOptions.MinimumTrialKeyLength} characters. Generate one with: openssl rand -base64 48");
        }

        if (options.AllowDevTokens && !environment.IsDevelopment() && !options.RequiresTrialKey)
        {
            return ValidateOptionsResult.Fail(
                $"{AuthOptions.SectionName}:{nameof(AuthOptions.AllowDevTokens)} is enabled in the "
                + $"'{environment.EnvironmentName}' environment without a "
                + $"{AuthOptions.SectionName}:{nameof(AuthOptions.TrialKey)}. Outside Development the "
                + "dev sign-in is only allowed behind a trial key.");
        }

        return ValidateOptionsResult.Success;
    }
}
