#!/usr/bin/env bash
# One-time: put the API on Fly.io with its own Postgres, secrets, and the trial key.
#
# Run from anywhere after `fly auth login` (the only step a person has to do — it opens a
# browser). Safe to re-run: every step checks whether it already happened. Prints the trial key
# at the end, once; it is the thing you hand to a friend together with the server address.
#
# Deploys after this are just: fly deploy --config backend/fly.toml   (or ops/fly-deploy.sh)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
backend="$(cd "$here/.." && pwd)"
app="slice-api"
db="slice-db"
region="arn"

say() { printf '\n▸ %s\n' "$*"; }

command -v fly >/dev/null || { echo "fly CLI saknas: brew install flyctl"; exit 1; }
fly auth whoami >/dev/null 2>&1 || { echo "Inte inloggad på Fly. Kör: fly auth login"; exit 1; }

say "App: $app"
if ! fly apps list --json | grep -q "\"Name\": *\"$app\""; then
  fly apps create "$app" --org personal
else
  echo "finns redan"
fi

say "Postgres: $db"
if ! fly apps list --json | grep -q "\"Name\": *\"$db\""; then
  fly postgres create \
    --name "$db" --region "$region" --org personal \
    --vm-size shared-cpu-1x --volume-size 1 --initial-cluster-size 1
else
  echo "finns redan"
fi

say "Kopplar databasen till appen"
# `attach` creates a database + user on the cluster and prints DATABASE_URL once. The API reads
# Npgsql's key=value form under Database:ConnectionString, so the URL is rewritten below.
if ! fly secrets list --app "$app" | grep -q "Database__ConnectionString"; then
  attach_out="$(fly postgres attach "$db" --app "$app" --yes 2>&1 | tee /dev/stderr)"
  url="$(printf '%s' "$attach_out" | grep -o 'postgres://[^ ]*' | head -1)"
  [ -n "$url" ] || { echo "Hittade ingen DATABASE_URL i attach-utskriften"; exit 1; }
  conn="$(python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse, parse_qs
u = urlparse(sys.argv[1])
q = parse_qs(u.query)
ssl = {"disable": "Disable", "require": "Require"}.get(q.get("sslmode", ["disable"])[0], "Disable")
print(f"Host={u.hostname};Port={u.port or 5432};Database={u.path.lstrip('/')};Username={u.username};Password={u.password};SSL Mode={ssl}")
PY
)"
  fly secrets set --app "$app" --stage "Database__ConnectionString=$conn" >/dev/null
  echo "Database__ConnectionString satt"
else
  echo "finns redan"
fi

say "Hemligheter"
if ! fly secrets list --app "$app" | grep -q "Auth__SigningKey"; then
  fly secrets set --app "$app" --stage "Auth__SigningKey=$(openssl rand -base64 48)" >/dev/null
  echo "Auth__SigningKey satt"
fi
trial_key=""
if ! fly secrets list --app "$app" | grep -q "Auth__TrialKey"; then
  trial_key="$(openssl rand -base64 36 | tr -d '/+=' | cut -c1-40)"
  fly secrets set --app "$app" --stage "Auth__TrialKey=$trial_key" >/dev/null
  echo "Auth__TrialKey satt"
fi

say "Deploy"
fly deploy --config "$backend/fly.toml" --app "$app"

say "Klart"
echo "Serveradress:  https://$app.fly.dev"
if [ -n "$trial_key" ]; then
  echo "Trial-nyckel:  $trial_key"
  echo "(visas bara nu — den går inte att läsa ut ur Fly igen; byt med: fly secrets set Auth__TrialKey=... --app $app)"
else
  echo "Trial-nyckeln sattes vid ett tidigare körning. Ny: fly secrets set --app $app \"Auth__TrialKey=\$(openssl rand -base64 36 | tr -d '/+=' | cut -c1-40)\""
fi
echo "Båda går in under Jag → Utvecklarverktyg (7 tryck på versionsraden) → Serveradress / Trial-nyckel, sedan omstart + Logga in."
