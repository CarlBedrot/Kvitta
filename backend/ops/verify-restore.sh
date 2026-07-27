#!/usr/bin/env bash
#
# Restores a backup into a scratch database and checks it came back intact.
#
# This is the part people skip, and skipping it is how a folder full of backups turns out to be a
# folder full of files. A backup nobody has restored is a hypothesis. Run this on a schedule, not
# once — the failure mode is silent, and by the time you need the dump it is far too late to find
# out that pg_dump was writing an error message into a .gz for a month.
#
#   ops/verify-restore.sh [backup-file]     (defaults to the newest backup)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="${KVITTA_PG_CONTAINER:-kvitta-postgres}"
USERNAME="${KVITTA_PG_USER:-kvitta}"
DATABASE="${KVITTA_PG_DATABASE:-kvitta}"
SCRATCH="kvitta_restore_check"

BACKUP="${1:-$(ls -1t "$HERE"/backups/kvitta-*.sql.gz 2>/dev/null | head -1)}"
if [ -z "${BACKUP:-}" ] || [ ! -f "$BACKUP" ]; then
    echo "no backup to verify (looked in $HERE/backups)" >&2
    exit 1
fi

echo "verifying $(basename "$BACKUP")"

psql_scratch() {
    docker exec -i "$CONTAINER" psql --username="$USERNAME" --dbname="$SCRATCH" -tA "$@"
}

cleanup() {
    docker exec "$CONTAINER" psql --username="$USERNAME" --dbname=postgres \
        -c "DROP DATABASE IF EXISTS $SCRATCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
docker exec "$CONTAINER" psql --username="$USERNAME" --dbname=postgres \
    -c "CREATE DATABASE $SCRATCH" >/dev/null

# Restored into a scratch database, never over the live one. A verification step that can destroy
# the thing it is verifying is worse than no verification step.
gunzip -c "$BACKUP" | docker exec -i "$CONTAINER" psql \
    --username="$USERNAME" --dbname="$SCRATCH" --quiet \
    --set ON_ERROR_STOP=on >/dev/null

FAILED=0
for TABLE in events groups members users refresh_tokens invites; do
    LIVE=$(docker exec "$CONTAINER" psql --username="$USERNAME" --dbname="$DATABASE" -tA \
        -c "SELECT count(*) FROM $TABLE" 2>/dev/null || echo "missing")
    COPY=$(psql_scratch -c "SELECT count(*) FROM $TABLE" 2>/dev/null || echo "missing")

    if [ "$LIVE" = "$COPY" ]; then
        printf '  %-16s %s rows\n' "$TABLE" "$COPY"
    else
        printf '  %-16s MISMATCH live=%s restored=%s\n' "$TABLE" "$LIVE" "$COPY" >&2
        FAILED=1
    fi
done

# The log is the only irreplaceable table, so it gets a stronger check than a row count: gap-free
# serverSeq per group is the invariant the client cursor depends on (design doc §8). A restore
# that lost a row in the middle would still match on totals if it also gained one elsewhere.
GAPS=$(psql_scratch -c "
    SELECT count(*) FROM (
        SELECT \"GroupId\",
               max(\"ServerSeq\") AS highest,
               count(*)          AS total
        FROM events GROUP BY \"GroupId\"
    ) g WHERE g.highest <> g.total")

if [ "$GAPS" != "0" ]; then
    echo "  events           GAPPED serverSeq in $GAPS group(s)" >&2
    FAILED=1
else
    echo "  events           serverSeq gap-free in every group"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "RESTORE VERIFICATION FAILED" >&2
    exit 1
fi

echo "restore verified"
