using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Kvitta.Api.Tests;

/// <summary>
/// Builds envelopes in exactly the shape KvittaCore encodes on the wire. Hand-written rather than
/// generated, so that if the Swift encoding ever drifts these tests notice.
/// </summary>
public sealed class GroupScenario(Guid? userId = null)
{
    public Guid GroupId { get; } = Guid.NewGuid();

    /// <summary>
    /// The signed-in user pushing this group. Defaults to a random id for tests that never get as
    /// far as writing a member row — anything that does must use
    /// <see cref="KvittaApiFixture.ScenarioAsync"/>, because <c>members.LinkedUserId</c> has a
    /// foreign key to <c>users</c> and only signing in creates that row.
    /// </summary>
    public Guid UserId { get; } = userId ?? Guid.NewGuid();

    public List<Guid> Members { get; } = [Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid()];

    public JsonObject GroupCreated(string currency = "SEK") => Envelope(
        GroupId,
        "GroupCreated",
        new JsonObject { ["name"] = "Fjällresan", ["currency"] = currency });

    /// <summary>The first member is linked to this device's user, which is what authorises pushes.</summary>
    public JsonObject MemberAdded(int index) => Envelope(
        Members[index],
        "MemberAdded",
        new JsonObject
        {
            ["displayName"] = $"Member {index + 1}",
            ["linkedUserId"] = index == 0 ? UserId.ToString() : null
        });

    /// <summary>The design doc's worked example: 437.00 kr three ways.</summary>
    public JsonObject ExpenseCreated(
        Guid? expenseId = null,
        long amountMinor = 43_700,
        long[]? shares = null,
        string currency = "SEK")
    {
        shares ??= [14_567, 14_567, 14_566];

        var shareLines = new JsonArray();
        for (var i = 0; i < shares.Length; i++)
        {
            shareLines.Add(new JsonObject
            {
                ["memberId"] = Members[i].ToString(),
                ["amountMinor"] = shares[i]
            });
        }

        return Envelope(
            expenseId ?? Guid.NewGuid(),
            "ExpenseCreated",
            new JsonObject
            {
                ["description"] = "Systembolaget",
                ["categoryId"] = "alkohol",
                ["date"] = "2026-07-21",
                ["currency"] = currency,
                ["amountMinor"] = amountMinor,
                ["payers"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["memberId"] = Members[0].ToString(),
                        ["amountMinor"] = amountMinor
                    }
                },
                ["shares"] = shareLines,
                ["splitMethod"] = "equal"
            });
    }

    /// <summary>Deactivates a member. The payload is empty — the entityId carries the whole meaning.</summary>
    public JsonObject MemberRemoved(int index) => Envelope(Members[index], "MemberRemoved", new JsonObject());

    public JsonObject UnknownType(string type = "CommentAdded") => Envelope(
        Guid.NewGuid(),
        type,
        new JsonObject
        {
            ["text"] = "vem drack all vin",
            ["reactions"] = new JsonArray { "🍷" },
            ["nested"] = new JsonObject { ["deep"] = 42 }
        });

    public JsonObject Envelope(Guid entityId, string type, JsonObject payload) => new()
    {
        ["eventId"] = Guid.NewGuid().ToString(),
        ["groupId"] = GroupId.ToString(),
        ["entityId"] = entityId.ToString(),
        ["type"] = type,
        ["schemaVersion"] = 1,
        ["authorId"] = UserId.ToString(),
        ["clientTimestamp"] = "2026-07-21T18:30:00Z",
        ["payload"] = payload
    };

    /// <summary>GroupCreated plus three members — the minimum for a group that can hold an expense.</summary>
    public JsonArray OpeningBatch() =>
    [
        GroupCreated(),
        MemberAdded(0),
        MemberAdded(1),
        MemberAdded(2)
    ];
}

public static class ApiClientExtensions
{
    public static Task<HttpResponseMessage> PushAsync(
        this HttpClient client,
        GroupScenario scenario,
        JsonArray batch,
        int? build = null)
    {
        var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"/api/v1/groups/{scenario.GroupId}/events")
        {
            Content = JsonContent.Create(batch)
        };

        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(scenario.UserId));
        if (build is { } value)
        {
            request.Headers.Add("X-Kvitta-Build", value.ToString());
        }

        return client.SendAsync(request);
    }

    public static Task<HttpResponseMessage> PullAsync(
        this HttpClient client,
        GroupScenario scenario,
        long after = 0,
        int? limit = null,
        Guid? asUser = null)
    {
        var url = $"/api/v1/groups/{scenario.GroupId}/events?after={after}"
            + (limit is { } value ? $"&limit={value}" : "");

        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser ?? scenario.UserId));
        return client.SendAsync(request);
    }

    public static Task<HttpResponseMessage> ListGroupsAsync(this HttpClient client, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/groups");
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return client.SendAsync(request);
    }

    public static Guid[] GroupIds(this JsonElement body) =>
        body.GetProperty("groupIds").EnumerateArray()
            .Select(item => item.GetGuid())
            .ToArray();

    public static async Task<JsonElement> ReadJsonAsync(this HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

    public static long[] AcceptedSeqs(this JsonElement body) =>
        body.GetProperty("accepted").EnumerateArray()
            .Select(item => item.GetProperty("serverSeq").GetInt64())
            .ToArray();

    public static (string Code, string Reason)[] Rejections(this JsonElement body) =>
        body.GetProperty("rejected").EnumerateArray()
            .Select(item => (
                item.GetProperty("code").GetString()!,
                item.GetProperty("reason").GetString()!))
            .ToArray();
}
