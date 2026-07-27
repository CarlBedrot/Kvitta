using System.Net;
using System.Text.Json.Nodes;

namespace Kvitta.Api.Tests;

/// <summary>
/// Design doc §7: "A removed member can no longer push or pull."
/// </summary>
/// <remarks>
/// Every one of these failed before <see cref="Kvitta.Api.Data.Membership"/> existed. The rule had
/// been written out three times — push, pull, and the group list — and all three copies compared
/// only <c>LinkedUserId</c>, so removing someone from a group took nothing away from them.
/// </remarks>
[Collection(nameof(KvittaApiCollection))]
public sealed class MembershipTests(KvittaApiFixture fixture)
{
    /// <summary>Opens a group and then removes the pushing user from it.</summary>
    private async Task<GroupScenario> GroupWithoutMeAsync()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        // Member 0 is the one linked to this user, which is what authorised the opening batch.
        var removal = await fixture.Client.PushAsync(scenario, [scenario.MemberRemoved(0)]);
        Assert.Equal(HttpStatusCode.OK, removal.StatusCode);

        return scenario;
    }

    [Fact]
    public async Task A_removed_member_can_no_longer_push()
    {
        var scenario = await GroupWithoutMeAsync();

        var response = await fixture.Client.PushAsync(scenario, [scenario.ExpenseCreated()]);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_removed_member_can_no_longer_pull()
    {
        var scenario = await GroupWithoutMeAsync();

        var response = await fixture.Client.PullAsync(scenario);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_removed_member_no_longer_sees_the_group_in_their_list()
    {
        var scenario = await GroupWithoutMeAsync();

        var body = await (await fixture.Client.ListGroupsAsync(scenario.UserId)).ReadJsonAsync();

        Assert.DoesNotContain(scenario.GroupId, body.GroupIds());
    }

    [Fact]
    public async Task The_batch_that_removes_you_still_lands()
    {
        // The guard runs once, before the loop. You were a member when you wrote the event, and
        // events are immutable — refusing it would strand the removal in the outbox forever.
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var response = await fixture.Client.PushAsync(
            scenario,
            new JsonArray { scenario.ExpenseCreated(), scenario.MemberRemoved(0) });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();
        Assert.Empty(body.Rejections());
        Assert.Equal([5, 6], body.AcceptedSeqs());
    }

    [Fact]
    public async Task An_active_member_is_unaffected()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var push = await fixture.Client.PushAsync(scenario, [scenario.ExpenseCreated()]);
        var pull = await fixture.Client.PullAsync(scenario);
        var groups = await (await fixture.Client.ListGroupsAsync(scenario.UserId)).ReadJsonAsync();

        Assert.Equal(HttpStatusCode.OK, push.StatusCode);
        Assert.Equal(HttpStatusCode.OK, pull.StatusCode);
        Assert.Contains(scenario.GroupId, groups.GroupIds());
    }
}
