using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Kvitta.Api.Migrations
{
    /// <inheritdoc />
    public partial class UserSwishNumber : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SwishNumber",
                table: "users",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SwishNumber",
                table: "users");
        }
    }
}
