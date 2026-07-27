import Foundation
import GRDB

/// The local database schema.
///
/// Three tables, and only one of them holds truth. `event` is the log; everything the user sees
/// is folded out of it at launch. `outbox` and `groupCursor` are sync bookkeeping — losing either
/// costs a re-push or a re-pull, both of which are idempotent, and neither can corrupt a balance.
enum Schema {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // The log. Append-only in spirit: the sole permitted update is stamping `serverSeq`
            // once the server assigns one, which records ordering rather than changing what
            // happened. Corrections are new events (CLAUDE.md), never edits to these rows.
            try db.create(table: "event") { table in
                // Client-generated, and the idempotency key end to end (design doc §2). As the
                // primary key it makes a re-delivered sync page free: the insert simply misses.
                table.primaryKey("eventId", .text).notNull()
                table.column("groupId", .text).notNull().indexed()
                // NULL until acknowledged — which is exactly "still in the outbox".
                table.column("serverSeq", .integer)
                table.column("clientTimestamp", .integer).notNull()
                table.column("receivedAt", .integer).notNull()
                // The encoded envelope. Deliberately the whole thing rather than a column per
                // field: `type`, `entityId` and `authorId` all live in here already, and copying
                // them out would create a second place for the same fact to be wrong, plus a
                // migration every time the envelope grows a field.
                table.column("payload", .blob).notNull()
            }

            // Replay order, straight out of the index: acknowledged events by the sequence the
            // server agreed on, then anything still pending.
            try db.create(
                index: "event_on_groupId_serverSeq",
                on: "event",
                columns: ["groupId", "serverSeq"]
            )

            try db.create(table: "outbox") { table in
                table.primaryKey("eventId", .text)
                    .notNull()
                    .references("event", onDelete: .cascade)
                table.column("queuedAt", .integer).notNull()
                // Kept so repeated push failures can be surfaced rather than retried in silence.
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
            }

            try db.create(table: "groupCursor") { table in
                table.primaryKey("groupId", .text).notNull()
                table.column("lastServerSeq", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2-rejected-events") { db in
            // `attemptCount`/`lastError` model a *transient* failure: try again later. A server
            // that refuses an event on its merits is a different thing — retrying forever would
            // spin, and dropping it is forbidden (CLAUDE.md; design doc §7 says the client
            // surfaces "these expenses could not sync" rather than silently dropping them).
            // These two columns are how an event leaves the retry queue without leaving the app.
            try db.alter(table: "outbox") { table in
                table.add(column: "rejectedAt", .integer)
                table.add(column: "rejectionCode", .text)
            }
        }

        return migrator
    }
}
