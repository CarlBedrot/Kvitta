using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

[Collection(nameof(KvittaApiCollection))]
public sealed class SyncEndpointTests(KvittaApiFixture fixture)
{
    [Fact]
    public async Task Push_assigns_a_gap_free_sequence_starting_at_one()
    {
        var scenario = await fixture.ScenarioAsync();

        var response = await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadJsonAsync();
        Assert.Equal([1, 2, 3, 4], body.AcceptedSeqs());
        Assert.Empty(body.Rejections());
    }

    [Fact]
    public async Task Pushing_the_same_batch_twice_changes_nothing()
    {
        var scenario = await fixture.ScenarioAsync();
        var batch = scenario.OpeningBatch();

        var first = await (await fixture.Client.PushAsync(scenario, batch)).ReadJsonAsync();
        var second = await (await fixture.Client.PushAsync(scenario, batch)).ReadJsonAsync();

        // Same sequence numbers the second time — the events keep the order they were first given.
        Assert.Equal(first.AcceptedSeqs(), second.AcceptedSeqs());

        await using var db = fixture.CreateDbContext();
        var stored = await db.Events.CountAsync(record => record.GroupId == scenario.GroupId);
        Assert.Equal(4, stored);
    }

    [Fact]
    public async Task Pull_returns_strictly_ordered_gap_free_pages()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var expenses = new JsonArray();
        for (var i = 0; i < 12; i++)
        {
            expenses.Add(scenario.ExpenseCreated());
        }

        await fixture.Client.PushAsync(scenario, expenses);

        var seen = new List<long>();
        long cursor = 0;
        while (true)
        {
            var page = await (await fixture.Client.PullAsync(scenario, after: cursor, limit: 5)).ReadJsonAsync();
            var seqs = page.GetProperty("events").EnumerateArray()
                .Select(item => item.GetProperty("serverSeq").GetInt64())
                .ToArray();

            if (seqs.Length == 0)
            {
                break;
            }

            seen.AddRange(seqs);
            cursor = page.GetProperty("nextCursor").GetInt64();
        }

        Assert.Equal(16, seen.Count);
        Assert.Equal(Enumerable.Range(1, 16).Select(value => (long)value), seen);
    }

    [Fact]
    public async Task An_expense_that_breaks_the_money_invariant_is_rejected_and_the_rest_still_lands()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var good = scenario.ExpenseCreated();
        // 14_567 + 14_567 + 14_565 = 43_699, one öre short of the stated amount.
        var bad = scenario.ExpenseCreated(shares: [14_567, 14_567, 14_565]);
        var alsoGood = scenario.ExpenseCreated();

        var body = await (await fixture.Client.PushAsync(scenario, [good, bad, alsoGood])).ReadJsonAsync();

        // The point: one bad event does not poison the batch, or it would sit at the head of the
        // outbox forever and block every good event behind it.
        Assert.Equal(2, body.AcceptedSeqs().Length);

        var rejections = body.Rejections();
        var rejection = Assert.Single(rejections);
        Assert.Equal("money_invariant_violated", rejection.Code);
        Assert.Contains("43699", rejection.Reason);
    }

    [Fact]
    public async Task An_expense_naming_a_stranger_is_rejected()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var stranger = Guid.NewGuid();
        var expense = scenario.Envelope(Guid.NewGuid(), "ExpenseCreated", new JsonObject
        {
            ["description"] = "Okänd",
            ["categoryId"] = "ovrigt",
            ["date"] = "2026-07-21",
            ["currency"] = "SEK",
            ["amountMinor"] = 1_000,
            ["payers"] = new JsonArray
            {
                new JsonObject { ["memberId"] = scenario.Members[0].ToString(), ["amountMinor"] = 1_000 }
            },
            ["shares"] = new JsonArray
            {
                new JsonObject { ["memberId"] = stranger.ToString(), ["amountMinor"] = 1_000 }
            },
            ["splitMethod"] = "exact"
        });

        var body = await (await fixture.Client.PushAsync(scenario, [expense])).ReadJsonAsync();
        Assert.Equal("unknown_member", Assert.Single(body.Rejections()).Code);
    }

    [Fact]
    public async Task An_expense_in_another_currency_is_accepted()
    {
        // M7: a group holds SEK and DKK side by side — each currency is its own sub-ledger on
        // the clients, and the server's job is to store what the log can hold, not to referee it.
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var body = await (await fixture.Client.PushAsync(
            scenario,
            [scenario.ExpenseCreated(currency: "DKK")])).ReadJsonAsync();

        Assert.Empty(body.Rejections());
        Assert.Single(body.AcceptedSeqs());
    }

    [Fact]
    public async Task A_currency_that_is_not_currency_shaped_is_rejected()
    {
        // Any real ISO code passes; "kronor" is not a code and would poison every client's
        // bucketing, so it is refused at the door as malformed.
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var body = await (await fixture.Client.PushAsync(
            scenario,
            [scenario.ExpenseCreated(currency: "kronor")])).ReadJsonAsync();

        Assert.Equal("malformed_payload", Assert.Single(body.Rejections()).Code);
    }

    [Fact]
    public async Task A_batch_for_an_unknown_group_that_does_not_open_with_GroupCreated_is_refused()
    {
        var scenario = await fixture.ScenarioAsync();

        var response = await fixture.Client.PushAsync(scenario, [scenario.MemberAdded(0)]);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_stranger_cannot_push_to_someone_elses_group()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        // Same group, different user, and that user is linked to no member in it.
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

    [Fact]
    public async Task An_event_type_the_server_has_never_heard_of_survives_a_round_trip()
    {
        var scenario = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var unknown = scenario.UnknownType();
        var pushed = await (await fixture.Client.PushAsync(scenario, [unknown])).ReadJsonAsync();

        // Accepted, not rejected: the server is a fan-out layer and an unknown type cannot move
        // money. Rejecting would strand a newer client's data permanently.
        Assert.Single(pushed.AcceptedSeqs());
        Assert.Empty(pushed.Rejections());

        var page = await (await fixture.Client.PullAsync(scenario, after: 4)).ReadJsonAsync();
        var returned = page.GetProperty("events").EnumerateArray().Single();

        Assert.Equal("CommentAdded", returned.GetProperty("type").GetString());
        var payload = returned.GetProperty("payload");
        Assert.Equal("vem drack all vin", payload.GetProperty("text").GetString());
        Assert.Equal(42, payload.GetProperty("nested").GetProperty("deep").GetInt32());
        Assert.Equal("🍷", payload.GetProperty("reactions")[0].GetString());
    }

    [Fact]
    public async Task Pull_refuses_a_non_member_and_404s_an_unknown_group()
    {
        var scenario = await fixture.ScenarioAsync();

        var missing = await fixture.Client.PullAsync(scenario);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);

        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        var stranger = await fixture.Client.PullAsync(scenario, asUser: Guid.NewGuid());
        Assert.Equal(HttpStatusCode.Forbidden, stranger.StatusCode);
    }

    [Fact]
    public async Task A_build_below_the_minimum_is_told_to_upgrade()
    {
        var client = fixture.CreateClient(new Dictionary<string, string?>
        {
            ["Sync:MinimumClientBuild"] = "42"
        });

        var scenario = await fixture.ScenarioAsync();

        var tooOld = await client.PushAsync(scenario, scenario.OpeningBatch(), build: 41);
        Assert.Equal(HttpStatusCode.UpgradeRequired, tooOld.StatusCode);

        var current = await client.PushAsync(scenario, scenario.OpeningBatch(), build: 42);
        Assert.Equal(HttpStatusCode.OK, current.StatusCode);
    }

    [Fact]
    public async Task Health_is_reachable()
    {
        var response = await fixture.Client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
