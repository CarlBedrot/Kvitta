using System.Net;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

/// <summary>
/// What a signed-in caller may claim inside the events they push.
/// </summary>
/// <remarks>
/// Authentication only settles who is speaking. These are the checks on what they are allowed to
/// say — both of which were entirely absent before M4, so a member could author events in a
/// friend's name and invent user accounts by naming them.
/// </remarks>
[Collection(nameof(KvittaApiCollection))]
public sealed class EventAuthorshipTests(KvittaApiFixture fixture)
{
    [Fact]
    public async Task An_event_authored_as_somebody_else_is_rejected()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var forged = scenario.ExpenseCreated();
        forged["authorId"] = Guid.NewGuid().ToString();

        var body = await (await fixture.Client.PushAsync(scenario, [forged])).ReadJsonAsync();

        Assert.Equal("author_mismatch", Assert.Single(body.Rejections()).Code);
    }

    [Fact]
    public async Task A_forged_event_does_not_take_the_rest_of_the_batch_with_it()
    {
        // Per-event, not a 403 for the whole push. CLAUDE.md is explicit that a batch is an outbox
        // drain: refusing all of it would park one bad event at the head of the queue and block
        // every good one behind it forever.
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var forged = scenario.ExpenseCreated();
        forged["authorId"] = Guid.NewGuid().ToString();

        var response = await fixture.Client.PushAsync(
            scenario,
            new JsonArray { scenario.ExpenseCreated(), forged, scenario.ExpenseCreated() });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();
        Assert.Equal(2, body.AcceptedSeqs().Length);
        Assert.Equal("author_mismatch", Assert.Single(body.Rejections()).Code);
    }

    [Fact]
    public async Task A_member_linked_to_somebody_else_is_rejected()
    {
        var scenario = await fixture.ScenarioAsync();

        var claimed = Guid.NewGuid();
        var batch = new JsonArray
        {
            scenario.GroupCreated(),
            scenario.MemberAdded(0),
            scenario.Envelope(
                Guid.NewGuid(),
                "MemberAdded",
                new JsonObject
                {
                    ["displayName"] = "Someone else's account",
                    ["linkedUserId"] = claimed.ToString()
                })
        };

        var body = await (await fixture.Client.PushAsync(scenario, batch)).ReadJsonAsync();

        Assert.Equal("unauthorized_link", Assert.Single(body.Rejections()).Code);

        // And crucially, no user row was conjured up for the id it named.
        await using var db = fixture.CreateDbContext();
        Assert.False(await db.Users.AnyAsync(user => user.Id == claimed));
    }

    [Fact]
    public async Task A_placeholder_member_with_no_linked_user_is_still_fine()
    {
        // Design doc §5: splitting with people who never install the app is the whole point.
        var scenario = await fixture.ScenarioAsync();

        var body = await (await fixture.Client.PushAsync(scenario, scenario.OpeningBatch())).ReadJsonAsync();

        Assert.Equal(4, body.AcceptedSeqs().Length);
        Assert.Empty(body.Rejections());

        await using var db = fixture.CreateDbContext();
        var placeholders = await db.Members
            .CountAsync(member => member.GroupId == scenario.GroupId && member.LinkedUserId == null);
        Assert.Equal(2, placeholders);
    }

    [Fact]
    public async Task Creating_a_group_without_joining_it_is_refused()
    {
        // Otherwise the creator ends up with a group they are not a member of: this push succeeds
        // and every later one 403s, which from the outside is indistinguishable from a server bug.
        var scenario = await fixture.ScenarioAsync();

        var response = await fixture.Client.PushAsync(
            scenario,
            new JsonArray { scenario.GroupCreated(), scenario.MemberAdded(1) });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_second_push_from_the_group_creator_is_accepted()
    {
        // The control for the rule above: the bootstrap really did make them a member.
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var response = await fixture.Client.PushAsync(scenario, [scenario.ExpenseCreated()]);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
