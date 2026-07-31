using Kvitta.Api.Auth;
using Kvitta.Api.Data;
using Kvitta.Api.Endpoints;
using Kvitta.Api.Options;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using System.Threading.RateLimiting;

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

builder.Services
    .AddOptions<AuthOptions>()
    .Bind(builder.Configuration.GetSection(AuthOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddSingleton<IValidateOptions<AuthOptions>, AuthOptionsGuard>();
builder.Services.AddSingleton<TokenIssuer>();

// Authentication only — deliberately no AddAuthorization and no RequireAuthorization.
//
// UseAuthentication just populates HttpContext.User and never short-circuits, whereas the
// authorization middleware challenges before the endpoint runs. That distinction matters here: an
// old client with no token must get 426 Upgrade Required (§9) rather than 401, and the upgrade
// check is the first line of every handler. Letting authorization answer first would take the
// forced-update screen away from exactly the clients that need it.
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services
    .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<AuthOptions>>((jwt, auth) =>
    {
        // Without this, the handler silently renames `sub` to ClaimTypes.NameIdentifier and every
        // lookup of the subject comes back empty.
        jwt.MapInboundClaims = false;

        jwt.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = auth.Value.Issuer,
            ValidateAudience = true,
            ValidAudience = auth.Value.Audience,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = TokenIssuer.SigningKey(auth.Value),
            // Pinned, so a token claiming "alg": "none" or an asymmetric algorithm is not even
            // considered. Algorithm confusion is the classic way a JWT check gets bypassed.
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddDbContext<KvittaDbContext>((provider, options) =>
{
    var database = provider.GetRequiredService<IOptions<DatabaseOptions>>().Value;
    options.UseNpgsql(database.ConnectionString);
});

builder.Services.AddScoped<EventWriter>();
builder.Services.AddScoped<RefreshTokenService>();
builder.Services.AddScoped<AppleIdentityVerifier>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddProblemDetails();

// Apple's signing keys, fetched and cached by the standard retriever. Registered as the key source
// so the verifier itself stays concrete: tests swap this one registration for a static key and the
// real validation code — signature, issuer, audience, expiry, algorithm — is what runs under test.
builder.Services.AddSingleton<IConfigurationManager<OpenIdConnectConfiguration>>(provider =>
{
    var auth = provider.GetRequiredService<IOptions<AuthOptions>>().Value;
    return new ConfigurationManager<OpenIdConnectConfiguration>(
        auth.AppleMetadataAddress,
        new OpenIdConnectConfigurationRetriever(),
        new HttpDocumentRetriever());
});

// Auth is the only surface that takes unauthenticated volume, so it is the only one worth a limit.
//
// Partitioned by caller. A single un-partitioned window would be a denial-of-service handed to
// anybody who wants one: one client hammering sign-in would spend the allowance for everyone and
// lock the whole friend group out of their own app.
builder.Services.AddRateLimiter(limiter =>
{
    limiter.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    limiter.AddPolicy("auth", context =>
    {
        var auth = context.RequestServices.GetRequiredService<IOptions<AuthOptions>>().Value;

        return RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                Window = TimeSpan.FromMinutes(1),
                PermitLimit = auth.AuthAttemptsPerMinute,
                QueueLimit = 0
            });
    });
});

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseRateLimiter();
app.UseAuthentication();

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

app.MapAuthEndpoints(app.Environment);
app.MapInviteEndpoints();
app.MapProfileEndpoints();
app.MapEventEndpoints();

app.Run();

/// <summary>Exposed so the integration tests can drive the real host through WebApplicationFactory.</summary>
public partial class Program;
