using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Kvitta.Api.Migrations
{
    /// <inheritdoc />
    public partial class GroupPhoto : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<byte[]>(
                name: "PhotoJpeg",
                table: "groups",
                type: "bytea",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PhotoJpeg",
                table: "groups");
        }
    }
}
