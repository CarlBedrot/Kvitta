using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Tests;

/// <summary>
/// The row lock is the one piece of this server that is genuinely hard to get right, and the only
/// piece whose failure mode is silent: without it, two concurrent pushes read the same
/// <c>MAX(server_seq)</c> and either collide on the primary key or leave a gap. A gap is worse
/// than a crash — the client's cursor steps over it and an expense simply never arrives.
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class ConcurrencyTests(KvittaApiFixture fixture)
{
    [Fact]
    public async Task Parallel_pushes_to_one_group_produce_a_strictly_increasing_gap_free_sequence()
    {
        var scenario = new GroupScenario();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        const int writers = 8;
        const int perWriter = 5;

        var pushes = Enumerable.Range(0, writers).Select(async _ =>
        {
            var batch = new JsonArray();
            for (var i = 0; i < perWriter; i++)
            {
                batch.Add(scenario.ExpenseCreated());
            }

            var response = await fixture.Client.PushAsync(scenario, batch);
            return (await response.ReadJsonAsync()).AcceptedSeqs();
        });

        var results = await Task.WhenAll(pushes);
        var assigned = results.SelectMany(seqs => seqs).OrderBy(seq => seq).ToArray();

        var expected = 4 + (writers * perWriter);
        Assert.Equal(expected - 4, assigned.Length);

        // No duplicates, no gaps: 5..44 exactly once each, on top of the opening batch's 1..4.
        Assert.Equal(
            Enumerable.Range(5, writers * perWriter).Select(value => (long)value),
            assigned);

        await using var db = fixture.CreateDbContext();
        var stored = await db.Events
            .Where(record => record.GroupId == scenario.GroupId)
            .Select(record => record.ServerSeq)
            .OrderBy(seq => seq)
            .ToListAsync();

        Assert.Equal(expected, stored.Count);
        Assert.Equal(stored.Distinct().Count(), stored.Count);
        Assert.Equal(Enumerable.Range(1, expected).Select(value => (long)value), stored);
    }

    [Fact]
    public async Task Pushing_the_same_batch_from_two_callers_at_once_stores_it_once()
    {
        var scenario = new GroupScenario();
        await fixture.Client.PushAsync(scenario, scenario.OpeningBatch());

        // The same events, twice, concurrently — what a retry racing its own original looks like.
        var batch = new JsonArray();
        for (var i = 0; i < 4; i++)
        {
            batch.Add(scenario.ExpenseCreated());
        }

        var duplicate = JsonNode.Parse(batch.ToJsonString())!.AsArray();

        var responses = await Task.WhenAll(
            fixture.Client.PushAsync(scenario, batch),
            fixture.Client.PushAsync(scenario, duplicate));

        foreach (var response in responses)
        {
            response.EnsureSuccessStatusCode();
        }

        await using var db = fixture.CreateDbContext();
        var stored = await db.Events.CountAsync(record => record.GroupId == scenario.GroupId);

        Assert.Equal(8, stored); // 4 opening + 4 expenses, not 12
    }
}
