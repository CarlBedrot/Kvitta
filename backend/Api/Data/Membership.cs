using System.Linq.Expressions;

namespace Kvitta.Api.Data;

/// <summary>
/// The single definition of "this user may act in this group".
/// </summary>
/// <remarks>
/// This exists because the rule was previously written out twice — once in <see cref="EventWriter"/>
/// for push and once inline in the pull endpoint — and both copies forgot <c>IsActive</c>. Design
/// doc §7 requires that a removed member can no longer push or pull, and neither copy enforced it.
/// A third near-copy in the group-list endpoint had the same gap, which let a removed member keep
/// seeing a group they could no longer read.
///
/// One expression, used by every caller. The in-memory path compiles it rather than restating it:
/// compilation costs a few microseconds once per push batch, which is a fair price for the rule
/// having exactly one spelling.
/// </remarks>
public static class Membership
{
    public static Expression<Func<MemberRecord, bool>> Authorising(Guid userId) =>
        member => member.LinkedUserId == userId && member.IsActive;

    /// <summary>For callers that already hold the group's member rows in memory.</summary>
    public static bool IsAuthorised(IEnumerable<MemberRecord> members, Guid userId) =>
        members.Any(Authorising(userId).Compile());
}
