using Kvitta.Api.Data;
using Kvitta.Api.Endpoints;
using Kvitta.Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

// Configuration through IOptions only. CLAUDE.md forbids Environment.GetEnvironmentVariable —
// this is the one place the app learns anything about its surroundings.
builder.Services
    .AddOptions<DatabaseOptions>()
    .Bind(builder.Configuration.GetSection(DatabaseOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<SyncOptions>()
    .Bind(builder.Configuration.GetSection(SyncOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddDbContext<KvittaDbContext>((provider, options) =>
{
    var database = provider.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    options.UseNpgsql(database.ConnectionString);
});

builder.Services.AddScoped<EventWriter>();
builder.Services.AddProblemDetails();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();

using (var scope = app.Services.CreateScope())
{
    var database = scope.ServiceProvider.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    if (database.MigrateOnStartup)
    {
        await scope.ServiceProvider.GetRequiredService<KvittaDbContext>().Database.MigrateAsync();
    }
}

// M6's uptime monitor wants this, and it costs nothing now.
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapEventEndpoints();

app.Run();

/// <summary>Exposed so the integration tests can drive the real host through WebApplicationFactory.</summary>
public partial class Program;
