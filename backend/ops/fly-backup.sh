#!/usr/bin/env bash
# Read-only logical backup of the hosted database. Requires an authenticated Fly CLI.
# No database password passes through this machine; pg_dump uses the database's local socket.
#   ops/fly-backup.sh [private-destination-directory]
set -euo pipefail
umask 077

DESTINATION="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backups}"
mkdir -p "$DESTINATION"
TARGET="$DESTINATION/slice-$(date -u +%Y%m%dT%H%M%SZ)-$$.sql.gz"
PARTIAL="$TARGET.partial"
trap 'rm -f "$PARTIAL"' EXIT

# Fly Postgres Flex's server uses port 5433; 5432 is its network proxy. Quiet SSH and no
# PTY keep progress text out of the SQL stream. A failed dump never becomes a final backup.
fly ssh console --quiet --app slice-db --command \
    'pg_dump -p 5433 -U postgres -d slice_api --no-password --clean --if-exists --no-owner --no-privileges' \
    | gzip > "$PARTIAL"
gzip -t "$PARTIAL"
mv "$PARTIAL" "$TARGET"
echo "wrote $TARGET"
