using Kvitta.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Endpoints;

public static class HealthEndpoints
{
    public static void MapHealthEndpoints(this IEndpointRouteBuilder routes)
    {
        // Liveness is independent of Postgres: a database outage should not restart the API.
        routes.MapGet("/health/live", (HttpContext http) =>
        {
            http.Response.Headers.CacheControl = "no-store";
            return Results.Ok(new { status = "ok" });
        });
        // Keep the existing URL so Fly and external monitors gain the stronger check together.
        routes.MapGet("/health", ReadinessAsync);
    }

    private static async Task<IResult> ReadinessAsync(KvittaDbContext db, HttpContext http)
    {
        http.Response.Headers.CacheControl = "no-store";
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(http.RequestAborted);
        // Fly gives the probe five seconds; return an explicit failure before its timeout.
        deadline.CancelAfter(TimeSpan.FromSeconds(3));
        var ready = false;
        try
        {
            ready = await db.Database.CanConnectAsync(deadline.Token);
        }
        catch (OperationCanceledException) when (!http.RequestAborted.IsCancellationRequested)
        {
            // A timed-out dependency is unavailable, not a successful process-only check.
        }

        // No connection strings, exception messages, or database details in the public response.
        return ready
            ? Results.Ok(new { status = "ok" })
            : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
}
