using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Kvitta.Api.Migrations
{
    /// <inheritdoc />
    public partial class InitialSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "groups",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Currency = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_groups", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AppleSub = table.Column<string>(type: "text", nullable: true),
                    DisplayName = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "events",
                columns: table => new
                {
                    GroupId = table.Column<Guid>(type: "uuid", nullable: false),
                    ServerSeq = table.Column<long>(type: "bigint", nullable: false),
                    EventId = table.Column<Guid>(type: "uuid", nullable: false),
                    EntityId = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<string>(type: "text", nullable: false),
                    SchemaVersion = table.Column<int>(type: "integer", nullable: false),
                    AuthorId = table.Column<Guid>(type: "uuid", nullable: false),
                    ClientTimestamp = table.Column<string>(type: "text", nullable: false),
                    Payload = table.Column<string>(type: "jsonb", nullable: false),
                    ReceivedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_events", x => new { x.GroupId, x.ServerSeq });
                    table.ForeignKey(
                        name: "FK_events_groups_GroupId",
                        column: x => x.GroupId,
                        principalTable: "groups",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "invites",
                columns: table => new
                {
                    Token = table.Column<Guid>(type: "uuid", nullable: false),
                    GroupId = table.Column<Guid>(type: "uuid", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Revoked = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_invites", x => x.Token);
                    table.ForeignKey(
                        name: "FK_invites_groups_GroupId",
                        column: x => x.GroupId,
                        principalTable: "groups",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "members",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    GroupId = table.Column<Guid>(type: "uuid", nullable: false),
                    LinkedUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    DisplayName = table.Column<string>(type: "text", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_members", x => x.Id);
                    table.ForeignKey(
                        name: "FK_members_groups_GroupId",
                        column: x => x.GroupId,
                        principalTable: "groups",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_members_users_LinkedUserId",
                        column: x => x.LinkedUserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "IX_events_EventId",
                table: "events",
                column: "EventId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_invites_GroupId",
                table: "invites",
                column: "GroupId");

            migrationBuilder.CreateIndex(
                name: "IX_members_GroupId",
                table: "members",
                column: "GroupId");

            migrationBuilder.CreateIndex(
                name: "IX_members_LinkedUserId",
                table: "members",
                column: "LinkedUserId");

            migrationBuilder.CreateIndex(
                name: "IX_users_AppleSub",
                table: "users",
                column: "AppleSub",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "events");

            migrationBuilder.DropTable(
                name: "invites");

            migrationBuilder.DropTable(
                name: "members");

            migrationBuilder.DropTable(
                name: "groups");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
