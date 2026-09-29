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
SCRATCH="kvitta_restore_$(date -u +%Y%m%d%H%M%S)_$$"
CREATED=0

BACKUP="${1:-$(ls -1t "$HERE"/backups/kvitta-*.sql.gz 2>/dev/null | sed -n '1p' || true)}"
if [ -z "${BACKUP:-}" ] || [ ! -f "$BACKUP" ]; then
    echo "no backup to verify (looked in $HERE/backups)" >&2
    exit 1
fi

echo "verifying $(basename "$BACKUP")"
gzip -t "$BACKUP"

psql_scratch() {
    docker exec -i "$CONTAINER" psql --no-psqlrc --set ON_ERROR_STOP=on \
        --username="$USERNAME" --dbname="$SCRATCH" -tA "$@"
}

cleanup() {
    [ "$CREATED" -eq 1 ] || return 0
    docker exec "$CONTAINER" psql --no-psqlrc --set ON_ERROR_STOP=on --username="$USERNAME" --dbname=postgres \
        -c "DROP DATABASE IF EXISTS $SCRATCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec "$CONTAINER" psql --no-psqlrc --set ON_ERROR_STOP=on --username="$USERNAME" --dbname=postgres \
    -c "CREATE DATABASE $SCRATCH" >/dev/null
CREATED=1

# Restored into a scratch database, never over the live one. A verification step that can destroy
# the thing it is verifying is worse than no verification step.
gunzip -c "$BACKUP" | docker exec -i "$CONTAINER" psql \
    --no-psqlrc --username="$USERNAME" --dbname="$SCRATCH" --quiet \
    --set ON_ERROR_STOP=on >/dev/null

FAILED=0
for TABLE in events groups members users refresh_tokens invites; do
    # Missing tables or failed queries must fail. A historical backup cannot be compared to
    # current live counts: legitimate writes since the dump would look like corruption.
    COPY=$(psql_scratch -c "SELECT count(*) FROM $TABLE")
    printf '  %-16s %s rows\n' "$TABLE" "$COPY"
done

# The log is the only irreplaceable table, so it gets a stronger check than a row count: gap-free
# serverSeq per group is the invariant the client cursor depends on (design doc §8). A restore
# that lost a row in the middle would still match on totals if it also gained one elsewhere.
GAPS=$(psql_scratch -c "
    SELECT count(*) FROM (
        SELECT \"GroupId\",
               min(\"ServerSeq\") AS lowest,
               max(\"ServerSeq\") AS highest,
               count(*)          AS total,
               count(DISTINCT \"ServerSeq\") AS unique_total
        FROM events GROUP BY \"GroupId\"
    ) g WHERE g.lowest <> 1 OR g.highest <> g.total OR g.unique_total <> g.total")

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

echo "restore verified (required tables and event sequence integrity; not a live row-count comparison)"
