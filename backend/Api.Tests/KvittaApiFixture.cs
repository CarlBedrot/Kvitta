using System.Net.Http.Json;
using Kvitta.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Testcontainers.PostgreSql;

namespace Kvitta.Api.Tests;

/// <summary>
/// A real Postgres and a real host, for every test. Nothing here is mocked: these tests exist to
/// prove things about row locks, unique indexes and transaction boundaries, and none of those
/// survive being faked.
/// </summary>
public sealed class KvittaApiFixture : IAsyncLifetime
{
    private PostgreSqlContainer? _container;
    private WebApplicationFactory<Program>? _factory;

    public HttpClient Client { get; private set; } = null!;

    public string ConnectionString { get; private set; } = "";

    /// <summary>
    /// The signing key the test host runs with, so tests can mint their own tokens in-process.
    /// </summary>
    /// <remarks>
    /// Tests deliberately do not go through <c>POST /api/v1/auth/dev</c>. That endpoint is only
    /// ever mapped in the Development environment, and this host runs as Testing — widening the
    /// dev shortcut to cover the test environment is precisely how it would end up reachable
    /// somewhere real. Minting here uses the same <c>TokenIssuer</c> the app uses.
    /// </remarks>
    public const string SigningKey = "kvitta-test-signing-key-not-a-secret-32+";

    public const string Issuer = "https://kvitta.test";

    public const string Audience = "se.kvitta.app";

    private static Dictionary<string, string?> AuthSettings => new()
    {
        ["Auth:SigningKey"] = SigningKey,
        ["Auth:Issuer"] = Issuer,
        ["Auth:Audience"] = Audience,
        ["Auth:AppleBundleId"] = Audience,
        ["Auth:AllowDevTokens"] = "false",
        // Every test in the suite shares one loopback address, so the production-shaped per-caller
        // limit would read the whole run as a single client hammering sign-in. Raised rather than
        // disabled, so the limiter is still in the pipeline being exercised.
        ["Auth:AuthAttemptsPerMinute"] = "100000"
    };


    /// <summary>
    /// Set <c>KVITTA_TEST_POSTGRES</c> to a connection string to run against an existing server
    /// instead of a container — useful when no container runtime is up, and what CI will use.
    /// </summary>
    private static string? ExternalConnectionString =>
        Environment.GetEnvironmentVariable("KVITTA_TEST_POSTGRES");

    public async Task InitializeAsync()
    {
        if (ExternalConnectionString is { Length: > 0 } external)
        {
            ConnectionString = external;
        }
        else
        {
            // Pinned to the version docker-compose runs, so a test can never pass against a
            // Postgres that differs from the one the app talks to. Credentials are left to
            // Testcontainers, which generates them per run — nothing to commit, and no two runs
            // share one.
            _container = new PostgreSqlBuilder()
                .WithImage("postgres:17")
                .WithDatabase("kvitta_test")
                .Build();

            await _container.StartAsync();
            ConnectionString = _container.GetConnectionString();
        }

        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureTestServices(services => services.Replace(
                ServiceDescriptor.Singleton<IConfigurationManager<OpenIdConnectConfiguration>>(
                    AppleTestKeys.ConfigurationManager())));
            builder.ConfigureAppConfiguration((_, config) =>
            {
                var settings = new Dictionary<string, string?>(AuthSettings)
                {
                    ["Database:ConnectionString"] = ConnectionString,
                    ["Database:MigrateOnStartup"] = "false",
                    ["Sync:MaxPullLimit"] = "500",
                    ["Sync:MaxPushBatchSize"] = "500",
                    ["Sync:MaxPayloadBytes"] = "262144",
                    ["Sync:MinimumClientBuild"] = "0"
                };

                config.AddInMemoryCollection(settings);
            });
        });

        Client = _factory.CreateClient();

        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<KvittaDbContext>().Database.MigrateAsync();
    }

    /// <summary>
    /// A host with different options, for the settings-dependent tests.
    /// </summary>
    /// <param name="overrides">Configuration keys to change. A null value removes the key.</param>
    /// <param name="environment">
    /// Overridable because some guards are environment-dependent — the dev sign-in shortcut is only
    /// legal in Development, and the only honest way to test that refusal is to boot a host
    /// claiming to be something else.
    /// </param>
    public HttpClient CreateClient(Dictionary<string, string?> overrides, string environment = "Testing")
    {
        var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment(environment);
            builder.ConfigureTestServices(services => services.Replace(
                ServiceDescriptor.Singleton<IConfigurationManager<OpenIdConnectConfiguration>>(
                    AppleTestKeys.ConfigurationManager())));
            builder.ConfigureAppConfiguration((_, config) =>
            {
                var settings = new Dictionary<string, string?>(AuthSettings)
                {
                    ["Database:ConnectionString"] = ConnectionString,
                    ["Database:MigrateOnStartup"] = "false",
                    // Off by default here as in the shared host: appsettings.Development.json
                    // carries the real compat floor, and a test booting in Development is testing
                    // an environment guard, not the 426 gate. The gate's own tests override this.
                    ["Sync:MinimumClientBuild"] = "0"
                };

                foreach (var (key, value) in overrides)
                {
                    settings[key] = value;
                }

                config.AddInMemoryCollection(settings);
            });
        });

        return factory.CreateClient();
    }

    /// <summary>
    /// Signs a fresh user in with Apple and hands back a scenario belonging to them.
    /// </summary>
    /// <remarks>
    /// Tests go through the real sign-in rather than inventing a user id, because since M4 a
    /// <c>users</c> row is only ever created here. That is the point of the change — a user is
    /// somebody who authenticated, not a GUID a client once mentioned — and the foreign key from
    /// <c>members.LinkedUserId</c> makes it structural rather than a convention.
    /// </remarks>
    public async Task<GroupScenario> ScenarioAsync()
    {
        var identityToken = AppleTestKeys.IdentityToken(subject: $"000123.{Guid.NewGuid():N}.4711");

        var response = await Client.PostAsJsonAsync("/api/v1/auth/apple", new
        {
            identityToken,
            nonce = "test-nonce"
        });

        response.EnsureSuccessStatusCode();
        var body = await response.ReadJsonAsync();

        return new GroupScenario(body.GetProperty("userId").GetGuid());
    }

    public KvittaDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<KvittaDbContext>()
            .UseNpgsql(ConnectionString)
            .Options;

        return new KvittaDbContext(options);
    }

    public async Task DisposeAsync()
    {
        _factory?.Dispose();
        if (_container is not null)
        {
            await _container.DisposeAsync();
        }
    }
}

[CollectionDefinition(nameof(KvittaApiCollection))]
public sealed class KvittaApiCollection : ICollectionFixture<KvittaApiFixture>;
