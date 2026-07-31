using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

/// <summary>
/// The Swish-number profile field: set by its owner, served only to co-members.
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class ProfileTests(KvittaApiFixture fixture)
{
    private Task<HttpResponseMessage> PutProfile(string? swishNumber, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, "/api/v1/me/profile")
        {
            Content = JsonContent.Create(new { swishNumber })
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return fixture.Client.SendAsync(request);
    }

    private Task<HttpResponseMessage> GetPayees(Guid groupId, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/groups/{groupId}/payees");
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return fixture.Client.SendAsync(request);
    }

    [Fact]
    public async Task A_co_member_sees_your_number_keyed_by_your_member()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var setting = await PutProfile("46701234567", owner.UserId);
        Assert.Equal(HttpStatusCode.NoContent, setting.StatusCode);

        // Anyone in the group sees it — that is the whole point. The other member here is the
        // owner's own second device in spirit; membership, not identity, is the audience.
        var payees = await (await GetPayees(owner.GroupId, owner.UserId)).ReadJsonAsync();
        var entries = payees.GetProperty("payees");

        // Members[1] and Members[2] are placeholders with no linked user, and so can never
        // contribute a number: exactly one entry, the owner's member.
        Assert.Equal(1, entries.GetArrayLength());
        Assert.Equal(owner.Members[0], entries[0].GetProperty("memberId").GetGuid());
        Assert.Equal("46701234567", entries[0].GetProperty("swishNumber").GetString());
    }

    [Fact]
    public async Task A_stranger_cannot_read_payees()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());
        await PutProfile("46701234567", owner.UserId);

        var stranger = await fixture.ScenarioAsync();
        var response = await GetPayees(owner.GroupId, stranger.UserId);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_number_that_is_not_swish_shaped_is_refused()
    {
        var owner = await fixture.ScenarioAsync();
        await PutProfile("46701234567", owner.UserId);

        // The client normalises before sending, so letters or a too-short fragment arriving here
        // is a bug — refuse, and leave the stored number alone.
        foreach (var garbage in new[] { "070-123", "sju siffror", "46 70 123 45 67" })
        {
            var response = await PutProfile(garbage, owner.UserId);
            Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        }

        await using var db = fixture.CreateDbContext();
        var user = await db.Users.SingleAsync(u => u.Id == owner.UserId);
        Assert.Equal("46701234567", user.SwishNumber);
    }

    [Fact]
    public async Task Clearing_your_number_removes_it_from_payees()
    {
        // The reason this is a profile column and not an event: it can be taken back.
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());
        await PutProfile("46701234567", owner.UserId);

        var clearing = await PutProfile(null, owner.UserId);
        Assert.Equal(HttpStatusCode.NoContent, clearing.StatusCode);

        var payees = await (await GetPayees(owner.GroupId, owner.UserId)).ReadJsonAsync();
        Assert.Equal(0, payees.GetProperty("payees").GetArrayLength());
    }
}
