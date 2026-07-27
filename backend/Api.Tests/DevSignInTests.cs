using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.Options;

namespace Kvitta.Api.Tests;

/// <summary>
/// The development sign-in shortcut, and the four things stopping it reaching anywhere real.
/// </summary>
/// <remarks>
/// It exists only because Sign in with Apple needs a paid Apple Developer team to add the
/// entitlement; without one, the simulator cannot complete a real sign-in and there would be no way
/// to exercise the authenticated app at all. That is a good reason for it to exist and no reason at
/// all to trust it, so the guards get tested like anything else that could hand out accounts.
/// </remarks>
[Collection(nameof(KvittaApiCollection))]
public sealed class DevSignInTests(KvittaApiFixture fixture)
{
    [Fact]
    public async Task The_route_does_not_exist_when_the_option_is_off()
    {
        // 404 rather than 401 or 403, because it is never mapped — there is no handler to reach,
        // which is a stronger guarantee than any check inside one.
        var response = await fixture.Client.PostAsJsonAsync(
            "/api/v1/auth/dev",
            new { userId = Guid.NewGuid() });

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public void The_host_refuses_to_start_outside_Development_with_the_option_on(string environment)
    {
        // Staging matters as much as Production here: a real deployment, reachable, and the most
        // likely place for someone's leftover configuration to survive.
        //
        // Note this fires *before* the route-mapping guard rather than after it — the options
        // validation runs as the host starts, so the "mapped only in Development" rule never gets
        // the chance to matter outside Development. Which is the right order: a misconfigured host
        // that never starts cannot serve anything, mapped or not.
        var failure = Assert.Throws<OptionsValidationException>(() => fixture.CreateClient(
            new Dictionary<string, string?> { ["Auth:AllowDevTokens"] = "true" },
            environment: environment));

        Assert.Contains("AllowDevTokens", failure.Message);
    }

    [Fact]
    public async Task In_Development_it_issues_a_session_that_actually_works()
    {
        var client = fixture.CreateClient(
            new Dictionary<string, string?> { ["Auth:AllowDevTokens"] = "true" },
            environment: "Development");

        var userId = Guid.NewGuid();
        var response = await client.PostAsJsonAsync("/api/v1/auth/dev", new { userId });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();
        Assert.Equal(userId, body.GetProperty("userId").GetGuid());

        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/groups");
        request.Headers.Authorization = new("Bearer", body.GetProperty("accessToken").GetString());
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(request)).StatusCode);
    }

    [Fact]
    public async Task It_refuses_to_impersonate_an_account_that_signed_in_with_Apple()
    {
        // The last guard: even with the shortcut switched on, in the environment where it is
        // legal, it cannot be pointed at a real person's account.
        var real = await fixture.ScenarioAsync();

        var client = fixture.CreateClient(
            new Dictionary<string, string?> { ["Auth:AllowDevTokens"] = "true" },
            environment: "Development");

        var response = await client.PostAsJsonAsync("/api/v1/auth/dev", new { userId = real.UserId });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
