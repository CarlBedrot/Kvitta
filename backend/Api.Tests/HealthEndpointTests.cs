using System.Net;
using System.Text.Json;

namespace Kvitta.Api.Tests;

[Collection(nameof(KvittaApiCollection))]
public sealed class HealthEndpointTests(KvittaApiFixture fixture)
{
    [Fact]
    public async Task Readiness_checks_the_database_without_authentication()
    {
        var response = await fixture.Client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("ok", body.RootElement.GetProperty("status").GetString());
    }

    [Fact]
    public async Task Database_outage_fails_readiness_but_not_liveness()
    {
        using var client = fixture.CreateClient(new Dictionary<string, string?>
        {
            ["Database:ConnectionString"] = "Host=127.0.0.1;Port=1;Database=unavailable;Username=probe;Password=private-probe-value;Timeout=1"
        });
        client.Timeout = TimeSpan.FromSeconds(10);

        var ready = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, ready.StatusCode);
        Assert.True(ready.Headers.CacheControl?.NoStore);
        Assert.Equal("{\"status\":\"unavailable\"}", await ready.Content.ReadAsStringAsync());

        var live = await client.GetAsync("/health/live");
        Assert.Equal(HttpStatusCode.OK, live.StatusCode);
        Assert.True(live.Headers.CacheControl?.NoStore);
    }
}
