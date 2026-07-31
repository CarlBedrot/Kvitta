using Kvitta.Api.Auth;
using Kvitta.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Endpoints;

public sealed record UpdateProfileRequest(string? SwishNumber);

public sealed record PayeeEntry(Guid MemberId, string SwishNumber);

public sealed record PayeesResponse(IReadOnlyList<PayeeEntry> Payees);

/// <summary>
/// The user's own payment profile, and the co-members' numbers it makes visible.
/// </summary>
/// <remarks>
/// This is the "server-side profile field, not an event" that CLAUDE.md's payment rules point to:
/// a Swish number must never enter the immutable log, but a mutable column the owner controls has
/// none of that permanence. Numbers are only ever served to people who share a group with the
/// owner — it is the same audience that could already receive the number in a payment link, just
/// without the manual typing.
/// </remarks>
public static class ProfileEndpoints
{
    public static void MapProfileEndpoints(this IEndpointRouteBuilder routes)
    {
        routes.MapPut("/api/v1/me/profile", UpdateAsync);
        routes.MapGet("/api/v1/groups/{groupId:guid}/payees", PayeesAsync);
    }

    /// <summary>Sets or clears the caller's Swish number. Null or empty clears it.</summary>
    private static async Task<IResult> UpdateAsync(
        UpdateProfileRequest? request,
        HttpContext http,
        KvittaDbContext db,
        CancellationToken cancellationToken)
    {
        if (!CallerId.TryRead(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var number = Normalise(request?.SwishNumber);
        if (number is { } candidate && !IsSwishShaped(candidate))
        {
            // The client normalises before sending (SwishNumber.normalised), so anything else
            // arriving here is a bug or mischief — refuse rather than store garbage that would
            // be prefilled into somebody's payment link.
            return Results.Problem(
                title: "Not a Swish number",
                detail: "Expected 8–15 digits with country code, like 46701234567.",
                statusCode: StatusCodes.Status422UnprocessableEntity);
        }

        var user = await db.Users.SingleOrDefaultAsync(
            candidateUser => candidateUser.Id == userId,
            cancellationToken);

        if (user is null)
        {
            return Results.Problem(
                title: "Unknown user",
                detail: "The token's subject does not exist.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        user.SwishNumber = number;
        await db.SaveChangesAsync(cancellationToken);
        return Results.NoContent();
    }

    /// <summary>
    /// The Swish numbers of the group's members, keyed by member. Members only — the audience is
    /// exactly the people the owner already settles up with.
    /// </summary>
    private static async Task<IResult> PayeesAsync(
        Guid groupId,
        HttpContext http,
        KvittaDbContext db,
        CancellationToken cancellationToken)
    {
        if (!CallerId.TryRead(http, out var userId))
        {
            return Results.Problem(
                title: "Not signed in",
                detail: "A valid access token is required.",
                statusCode: StatusCodes.Status401Unauthorized);
        }

        var isMember = await db.Members
            .Where(member => member.GroupId == groupId)
            .AnyAsync(Membership.Authorising(userId), cancellationToken);

        if (!isMember)
        {
            return Results.Problem(
                title: "Not a member",
                detail: $"User {userId} is not a member of group {groupId}.",
                statusCode: StatusCodes.Status403Forbidden);
        }

        var payees = await db.Members
            .Where(member => member.GroupId == groupId
                && member.IsActive
                && member.LinkedUserId != null)
            .Join(
                db.Users.Where(user => user.SwishNumber != null),
                member => member.LinkedUserId,
                user => user.Id,
                (member, user) => new PayeeEntry(member.Id, user.SwishNumber!))
            .ToListAsync(cancellationToken);

        return Results.Ok(new PayeesResponse(payees));
    }

    private static string? Normalise(string? raw)
    {
        var trimmed = raw?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }

    /// <summary>Digits only, 8–15 of them — Swish's own bound on an alias.</summary>
    private static bool IsSwishShaped(string number) =>
        number.Length is >= 8 and <= 15 && number.All(char.IsAsciiDigit);
}
