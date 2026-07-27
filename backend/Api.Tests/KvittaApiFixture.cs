using Kvitta.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
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
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Database:ConnectionString"] = ConnectionString,
                    ["Database:MigrateOnStartup"] = "false",
                    ["Sync:MaxPullLimit"] = "500",
                    ["Sync:MaxPushBatchSize"] = "500",
                    ["Sync:MaxPayloadBytes"] = "262144",
                    ["Sync:MinimumClientBuild"] = "0"
                });
            });
        });

        Client = _factory.CreateClient();

        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<KvittaDbContext>().Database.MigrateAsync();
    }

    /// <summary>A host with different options, for the settings-dependent tests.</summary>
    public HttpClient CreateClient(Dictionary<string, string?> overrides)
    {
        var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                var settings = new Dictionary<string, string?>
                {
                    ["Database:ConnectionString"] = ConnectionString,
                    ["Database:MigrateOnStartup"] = "false"
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
