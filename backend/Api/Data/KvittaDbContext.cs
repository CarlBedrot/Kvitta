using Microsoft.EntityFrameworkCore;

namespace Kvitta.Api.Data;

public sealed class KvittaDbContext(DbContextOptions<KvittaDbContext> options) : DbContext(options)
{
    public DbSet<UserRecord> Users => Set<UserRecord>();
    public DbSet<GroupRecord> Groups => Set<GroupRecord>();
    public DbSet<MemberRecord> Members => Set<MemberRecord>();
    public DbSet<InviteRecord> Invites => Set<InviteRecord>();
    public DbSet<EventRecord> Events => Set<EventRecord>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<UserRecord>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(user => user.Id);
            entity.HasIndex(user => user.AppleSub).IsUnique();
        });

        model.Entity<GroupRecord>(entity =>
        {
            entity.ToTable("groups");
            entity.HasKey(group => group.Id);
        });

        model.Entity<MemberRecord>(entity =>
        {
            entity.ToTable("members");
            entity.HasKey(member => member.Id);
            entity.HasIndex(member => member.GroupId);
            entity.HasOne<GroupRecord>()
                .WithMany()
                .HasForeignKey(member => member.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
            entity.HasOne<UserRecord>()
                .WithMany()
                .HasForeignKey(member => member.LinkedUserId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        model.Entity<InviteRecord>(entity =>
        {
            entity.ToTable("invites");
            entity.HasKey(invite => invite.Token);
            entity.HasOne<GroupRecord>()
                .WithMany()
                .HasForeignKey(invite => invite.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        model.Entity<EventRecord>(entity =>
        {
            entity.ToTable("events");

            // (group_id, server_seq) per §8: the pull cursor reads straight down this key.
            entity.HasKey(record => new { record.GroupId, record.ServerSeq });

            // The idempotency key. A re-delivered push inserts nothing and reads back the
            // sequence it was given the first time.
            entity.HasIndex(record => record.EventId).IsUnique();

            entity.Property(record => record.Payload).HasColumnType("jsonb");

            entity.HasOne<GroupRecord>()
                .WithMany()
                .HasForeignKey(record => record.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
