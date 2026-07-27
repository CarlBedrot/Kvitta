using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

/// <summary>
/// Sign in with Apple, and the session it produces (design doc §7).
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class AuthEndpointTests(KvittaApiFixture fixture)
{
    private static string Subject() => $"000123.{Guid.NewGuid():N}.4711";

    private Task<HttpResponseMessage> SignInAsync(string identityToken, string nonce = "test-nonce", string? name = null) =>
        fixture.Client.PostAsJsonAsync("/api/v1/auth/apple", new
        {
            identityToken,
            nonce,
            displayName = name
        });

    // MARK: - The happy path

    [Fact]
    public async Task A_valid_identity_token_creates_a_user_and_returns_a_session()
    {
        var subject = Subject();

        var response = await SignInAsync(AppleTestKeys.IdentityToken(subject), name: "Carl");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();

        Assert.NotEqual(Guid.Empty, body.GetProperty("userId").GetGuid());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("accessToken").GetString()));
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("refreshToken").GetString()));
        Assert.True(body.GetProperty("expiresIn").GetInt32() > 0);

        await using var db = fixture.CreateDbContext();
        var user = await db.Users.SingleAsync(candidate => candidate.AppleSub == subject);
        Assert.Equal("Carl", user.DisplayName);
    }

    [Fact]
    public async Task Signing_in_twice_returns_the_same_user()
    {
        var subject = Subject();

        var first = await (await SignInAsync(AppleTestKeys.IdentityToken(subject))).ReadJsonAsync();
        var second = await (await SignInAsync(AppleTestKeys.IdentityToken(subject))).ReadJsonAsync();

        Assert.Equal(first.GetProperty("userId").GetGuid(), second.GetProperty("userId").GetGuid());
    }

    [Fact]
    public async Task The_access_token_it_returns_is_accepted_by_the_event_routes()
    {
        // The two halves of auth have to agree: what /auth/apple signs is what JwtBearer validates.
        // If the issuer, audience or algorithm drifted apart, everything above would still pass.
        var body = await (await SignInAsync(AppleTestKeys.IdentityToken(Subject()))).ReadJsonAsync();
        var token = body.GetProperty("accessToken").GetString()!;

        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/groups");
        request.Headers.Authorization = new("Bearer", token);
        var response = await fixture.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // MARK: - The ways a token can be wrong

    [Fact]
    public async Task A_token_for_a_different_app_is_refused()
    {
        // Without the audience check, an identity token minted for any other Apple-sign-in app
        // could be replayed straight into this one.
        var response = await SignInAsync(AppleTestKeys.IdentityToken(Subject(), audience: "com.someone.else"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_from_a_different_issuer_is_refused()
    {
        var response = await SignInAsync(AppleTestKeys.IdentityToken(Subject(), issuer: "https://evil.example"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task An_expired_token_is_refused()
    {
        var response = await SignInAsync(
            AppleTestKeys.IdentityToken(Subject(), expires: DateTimeOffset.UtcNow.AddHours(-1)));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_signed_by_someone_other_than_Apple_is_refused()
    {
        var response = await SignInAsync(
            AppleTestKeys.IdentityToken(Subject(), credentials: AppleTestKeys.ImposterCredentials()));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_symmetrically_signed_token_is_refused()
    {
        // Algorithm confusion: HS256 signed with a key the server already trusts for its own
        // tokens. Pinning RS256 is what stops this being a complete auth bypass.
        var response = await SignInAsync(
            AppleTestKeys.IdentityToken(Subject(), credentials: AppleTestKeys.AlgorithmConfusionCredentials()));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_whose_nonce_belongs_to_another_sign_in_is_refused()
    {
        var token = AppleTestKeys.IdentityToken(Subject(), rawNonce: "the-nonce-apple-saw");

        var response = await SignInAsync(token, nonce: "a-different-nonce");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_token_with_no_nonce_at_all_is_refused()
    {
        var response = await SignInAsync(AppleTestKeys.IdentityToken(Subject(), nonceClaim: ""));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Rubbish_is_refused_rather_than_crashing()
    {
        var response = await SignInAsync("not-a-jwt");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // MARK: - Refresh

    [Fact]
    public async Task Refreshing_rotates_the_token_and_kills_the_old_one()
    {
        var session = await (await SignInAsync(AppleTestKeys.IdentityToken(Subject()))).ReadJsonAsync();
        var original = session.GetProperty("refreshToken").GetString()!;

        var refreshed = await RefreshAsync(original);
        Assert.Equal(HttpStatusCode.OK, refreshed.StatusCode);

        var next = (await refreshed.ReadJsonAsync()).GetProperty("refreshToken").GetString()!;
        Assert.NotEqual(original, next);

        var replayed = await RefreshAsync(original);
        Assert.Equal(HttpStatusCode.Unauthorized, replayed.StatusCode);
    }

    [Fact]
    public async Task Reusing_a_rotated_token_revokes_the_whole_chain()
    {
        // The stolen-token case. Once a used link is presented again there is no way to tell the
        // thief from the rightful holder, so both lose the session — that is the point.
        var session = await (await SignInAsync(AppleTestKeys.IdentityToken(Subject()))).ReadJsonAsync();
        var original = session.GetProperty("refreshToken").GetString()!;

        var live = (await (await RefreshAsync(original)).ReadJsonAsync())
            .GetProperty("refreshToken").GetString()!;

        // Someone replays the spent one.
        Assert.Equal(HttpStatusCode.Unauthorized, (await RefreshAsync(original)).StatusCode);

        // The token that was still good a moment ago is now dead too.
        Assert.Equal(HttpStatusCode.Unauthorized, (await RefreshAsync(live)).StatusCode);
    }

    [Fact]
    public async Task An_unknown_refresh_token_is_refused()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await RefreshAsync("nonsense")).StatusCode);
    }

    [Fact]
    public async Task Concurrent_rotations_of_one_token_produce_exactly_one_winner()
    {
        // The conditional UPDATE is what makes this safe. A read-then-write would let both
        // requests through and hand out two live chains from a single token.
        var session = await (await SignInAsync(AppleTestKeys.IdentityToken(Subject()))).ReadJsonAsync();
        var original = session.GetProperty("refreshToken").GetString()!;

        var attempts = await Task.WhenAll(
            Enumerable.Range(0, 6).Select(_ => RefreshAsync(original)));

        Assert.Equal(1, attempts.Count(attempt => attempt.StatusCode == HttpStatusCode.OK));
    }

    private Task<HttpResponseMessage> RefreshAsync(string refreshToken) =>
        fixture.Client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken });
}
