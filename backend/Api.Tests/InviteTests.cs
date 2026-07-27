using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

/// <summary>
/// Invite links, and joining a group you were never in (design doc §5 and §7).
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class InviteTests(KvittaApiFixture fixture)
{
    private async Task<(GroupScenario Owner, Guid Token)> InvitedGroupAsync()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var response = await Post($"/api/v1/groups/{owner.GroupId}/invites", null, owner.UserId);
        response.EnsureSuccessStatusCode();
        var token = (await response.ReadJsonAsync()).GetProperty("token").GetGuid();

        return (owner, token);
    }

    private Task<HttpResponseMessage> Post(string path, object? body, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, path)
        {
            Content = JsonContent.Create(body ?? new { })
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return fixture.Client.SendAsync(request);
    }

    [Fact]
    public async Task Only_a_member_can_mint_an_invite()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var stranger = await fixture.ScenarioAsync();
        var response = await Post($"/api/v1/groups/{owner.GroupId}/invites", null, stranger.UserId);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Accepting_claims_a_placeholder_and_inherits_its_history()
    {
        // The point of design doc §5: expenses reference members, never users, so somebody can
        // join long after the spending and the books already add up for them.
        var (owner, token) = await InvitedGroupAsync();
        await fixture.Client.PushAsync(owner, [owner.ExpenseCreated()]);

        var joiner = await fixture.ScenarioAsync();
        var response = await Post(
            $"/api/v1/invites/{token}/accept",
            new { memberId = owner.Members[1] },
            joiner.UserId);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();
        Assert.Equal(owner.GroupId, body.GetProperty("groupId").GetGuid());
        Assert.Equal(owner.Members[1], body.GetProperty("memberId").GetGuid());

        await using var db = fixture.CreateDbContext();
        var member = await db.Members.SingleAsync(m => m.Id == owner.Members[1]);
        Assert.Equal(joiner.UserId, member.LinkedUserId);
    }

    [Fact]
    public async Task A_joiner_can_then_pull_the_whole_group()
    {
        var (owner, token) = await InvitedGroupAsync();
        await fixture.Client.PushAsync(owner, [owner.ExpenseCreated()]);

        var joiner = await fixture.ScenarioAsync();
        await Post($"/api/v1/invites/{token}/accept", new { memberId = owner.Members[1] }, joiner.UserId);

        // Everything from before they joined, including the event that let them in.
        var page = await (await fixture.Client.PullAsync(owner, asUser: joiner.UserId)).ReadJsonAsync();
        Assert.Equal(6, page.GetProperty("events").GetArrayLength());

        var groups = await (await fixture.Client.ListGroupsAsync(joiner.UserId)).ReadJsonAsync();
        Assert.Contains(owner.GroupId, groups.GroupIds());
    }

    [Fact]
    public async Task Accepting_without_naming_a_member_joins_as_a_new_one()
    {
        var (owner, token) = await InvitedGroupAsync();
        var joiner = await fixture.ScenarioAsync();

        var body = await (await Post(
            $"/api/v1/invites/{token}/accept",
            new { displayName = "Sara" },
            joiner.UserId)).ReadJsonAsync();

        var memberId = body.GetProperty("memberId").GetGuid();

        await using var db = fixture.CreateDbContext();
        var member = await db.Members.SingleAsync(m => m.Id == memberId);
        Assert.Equal("Sara", member.DisplayName);
        Assert.Equal(joiner.UserId, member.LinkedUserId);
    }

    [Fact]
    public async Task Accepting_the_same_invite_twice_does_not_create_a_second_member()
    {
        // Tapping a link twice, or a retry after a dropped response, must be harmless.
        var (owner, token) = await InvitedGroupAsync();
        var joiner = await fixture.ScenarioAsync();

        var first = await (await Post($"/api/v1/invites/{token}/accept", new { memberId = owner.Members[1] }, joiner.UserId)).ReadJsonAsync();
        var second = await (await Post($"/api/v1/invites/{token}/accept", null, joiner.UserId)).ReadJsonAsync();

        Assert.Equal(first.GetProperty("memberId").GetGuid(), second.GetProperty("memberId").GetGuid());

        await using var db = fixture.CreateDbContext();
        var mine = await db.Members.CountAsync(m => m.GroupId == owner.GroupId && m.LinkedUserId == joiner.UserId);
        Assert.Equal(1, mine);
    }

    [Fact]
    public async Task A_member_who_is_already_somebody_elses_cannot_be_claimed()
    {
        var (owner, token) = await InvitedGroupAsync();

        var first = await fixture.ScenarioAsync();
        await Post($"/api/v1/invites/{token}/accept", new { memberId = owner.Members[1] }, first.UserId);

        var second = await fixture.ScenarioAsync();
        var response = await Post($"/api/v1/invites/{token}/accept", new { memberId = owner.Members[1] }, second.UserId);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task An_unknown_token_is_a_404_and_a_revoked_one_is_a_410()
    {
        var joiner = await fixture.ScenarioAsync();
        Assert.Equal(
            HttpStatusCode.NotFound,
            (await Post($"/api/v1/invites/{Guid.NewGuid()}/accept", null, joiner.UserId)).StatusCode);

        var (_, token) = await InvitedGroupAsync();
        await using (var db = fixture.CreateDbContext())
        {
            var invite = await db.Invites.SingleAsync(i => i.Token == token);
            invite.Revoked = true;
            await db.SaveChangesAsync();
        }

        // 410 rather than 404, so the app can say "ask for a new link" instead of "check the code".
        Assert.Equal(
            HttpStatusCode.Gone,
            (await Post($"/api/v1/invites/{token}/accept", null, joiner.UserId)).StatusCode);
    }

    [Fact]
    public async Task An_expired_invite_is_refused()
    {
        var (_, token) = await InvitedGroupAsync();
        await using (var db = fixture.CreateDbContext())
        {
            var invite = await db.Invites.SingleAsync(i => i.Token == token);
            invite.ExpiresAt = DateTimeOffset.UtcNow.AddDays(-1);
            await db.SaveChangesAsync();
        }

        var joiner = await fixture.ScenarioAsync();
        var response = await Post($"/api/v1/invites/{token}/accept", null, joiner.UserId);

        Assert.Equal(HttpStatusCode.Gone, response.StatusCode);
    }

    [Fact]
    public async Task A_stranger_pushing_nothing_writes_nothing()
    {
        // An empty batch short-circuits before the membership check, so it answers 200 to anyone.
        // That is a considered shortcut, not a gap — but it deserves pinning, because "this
        // endpoint returned 200 to a non-member" is alarming until you know nothing was written.
        var (owner, _) = await InvitedGroupAsync();
        var stranger = await fixture.ScenarioAsync();

        await using var db = fixture.CreateDbContext();
        var before = await db.Events.CountAsync(e => e.GroupId == owner.GroupId);

        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v1/groups/{owner.GroupId}/events")
        {
            Content = JsonContent.Create(new System.Text.Json.Nodes.JsonArray())
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(stranger.UserId));
        var response = await fixture.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(before, await db.Events.CountAsync(e => e.GroupId == owner.GroupId));
    }

    [Fact]
    public async Task Accepting_does_not_let_you_write_anything_else()
    {
        // The invite authorises exactly one event, written by the server. It must not become a
        // general licence to push into a group you have not joined.
        var (owner, _) = await InvitedGroupAsync();
        var stranger = await fixture.ScenarioAsync();

        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v1/groups/{owner.GroupId}/events")
        {
            Content = JsonContent.Create(new System.Text.Json.Nodes.JsonArray { owner.ExpenseCreated() })
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(stranger.UserId));

        Assert.Equal(HttpStatusCode.Forbidden, (await fixture.Client.SendAsync(request)).StatusCode);
    }
}
