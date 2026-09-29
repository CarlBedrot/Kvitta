#!/usr/bin/env bash
#
# Dumps the Kvitta database to a compressed, timestamped file.
#
# The events table is the only thing here that cannot be reconstructed from anything else — it is
# the log every client replays. Losing it loses the friend group's money history, so this is the
# one piece of operational tooling that genuinely matters.
#
#   ops/backup.sh [destination-directory]
#
# Environment:
#   KVITTA_PG_CONTAINER  docker container running Postgres (default: kvitta-postgres)
#   KVITTA_PG_USER       (default: kvitta)
#   KVITTA_PG_DATABASE   (default: kvitta)
#   KVITTA_BACKUP_KEEP   how many backups to keep (default: 14)

set -euo pipefail
umask 077

DESTINATION="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backups}"
CONTAINER="${KVITTA_PG_CONTAINER:-kvitta-postgres}"
USERNAME="${KVITTA_PG_USER:-kvitta}"
DATABASE="${KVITTA_PG_DATABASE:-kvitta}"
KEEP="${KVITTA_BACKUP_KEEP:-14}"

if ! [[ "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
    echo "KVITTA_BACKUP_KEEP must be a positive integer" >&2
    exit 1
fi

mkdir -p "$DESTINATION"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET="$DESTINATION/kvitta-$STAMP-$$.sql.gz"
PARTIAL="$TARGET.partial"
trap 'rm -f "$PARTIAL"' EXIT

# --clean --if-exists so the dump can be restored over an existing database without hand-editing
# it at three in the morning, which is the only time anybody ever reads one of these.
docker exec "$CONTAINER" pg_dump \
    --username="$USERNAME" \
    --dbname="$DATABASE" \
    --clean --if-exists --no-owner --no-privileges \
  | gzip > "$PARTIAL"

# Publish only after pg_dump and compression succeeded. Actual schema/data integrity is checked
# separately by verify-restore.sh; a valid gzip alone is not proof of a usable backup.
if [ ! -s "$PARTIAL" ]; then
    echo "backup produced an empty file" >&2
    exit 1
fi
gzip -t "$PARTIAL"
mv "$PARTIAL" "$TARGET"

echo "wrote $TARGET ($(du -h "$TARGET" | cut -f1))"

# Retention, oldest first. Deliberately after the write, so a failure never deletes anything.
COUNT=$(ls -1 "$DESTINATION"/kvitta-*.sql.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -gt "$KEEP" ]; then
    ls -1 "$DESTINATION"/kvitta-*.sql.gz | sed -n "1,$((COUNT - KEEP))p" | while read -r old; do
        echo "pruning $(basename "$old")"
        rm -f "$old"
    done
fi
