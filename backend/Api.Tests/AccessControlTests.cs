using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;

namespace Kvitta.Api.Tests;

/// <summary>
/// What the event routes accept as proof of identity, now that <c>X-Kvitta-User-Id</c> is gone.
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class AccessControlTests(KvittaApiFixture fixture)
{
    private static HttpRequestMessage Push(GroupScenario scenario, string? token, int? build = null)
    {
        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v1/groups/{scenario.GroupId}/events")
        {
            Content = JsonContent.Create(scenario.OpeningBatch())
        };

        if (token is not null)
        {
            request.Headers.Authorization = new("Bearer", token);
        }

        if (build is { } value)
        {
            request.Headers.Add("X-Kvitta-Build", value.ToString());
        }

        return request;
    }

    [Fact]
    public async Task No_token_is_refused()
    {
        var response = await fixture.Client.SendAsync(Push(await fixture.ScenarioAsync(), token: null));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_signed_with_the_wrong_key_is_refused()
    {
        // The whole point of the milestone: a caller can no longer simply assert who they are.
        var scenario = await fixture.ScenarioAsync();
        var forged = TestTokens.AccessTokenFor(scenario.UserId, credentials: TestTokens.WrongKey());

        var response = await fixture.Client.SendAsync(Push(scenario, forged));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task An_expired_token_is_refused()
    {
        var scenario = await fixture.ScenarioAsync();
        var stale = TestTokens.AccessTokenFor(scenario.UserId, expires: DateTimeOffset.UtcNow.AddHours(-2));

        var response = await fixture.Client.SendAsync(Push(scenario, stale));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_issued_for_a_different_audience_is_refused()
    {
        var scenario = await fixture.ScenarioAsync();
        var wrongAudience = TestTokens.AccessTokenFor(scenario.UserId, audience: "com.someone.else");

        var response = await fixture.Client.SendAsync(Push(scenario, wrongAudience));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_from_a_different_issuer_is_refused()
    {
        var scenario = await fixture.ScenarioAsync();
        var wrongIssuer = TestTokens.AccessTokenFor(scenario.UserId, issuer: "https://evil.example");

        var response = await fixture.Client.SendAsync(Push(scenario, wrongIssuer));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task An_out_of_date_client_with_no_token_is_told_to_upgrade_not_to_sign_in()
    {
        // This is why the app registers authentication but never authorization: the authorization
        // middleware would challenge before the handler ran, and a client too old to hold a token
        // would get 401 forever instead of the forced-update screen that would actually fix it.
        var client = fixture.CreateClient(new Dictionary<string, string?>
        {
            ["Sync:MinimumClientBuild"] = "42"
        });

        var response = await client.SendAsync(Push(await fixture.ScenarioAsync(), token: null, build: 7));

        Assert.Equal(HttpStatusCode.UpgradeRequired, response.StatusCode);
    }

    [Fact]
    public async Task A_valid_token_for_a_non_member_is_forbidden_not_unauthorized()
    {
        // Authenticated and rejected are different answers, and the client acts on them
        // differently: one means sign in again, the other means you were removed from the group.
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v1/groups/{owner.GroupId}/events")
        {
            Content = JsonContent.Create(new JsonArray { owner.ExpenseCreated() })
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(Guid.NewGuid()));

        var response = await fixture.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
