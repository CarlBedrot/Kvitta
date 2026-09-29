#!/usr/bin/env bash
# Every deploy after the first: build the image on Fly, roll it out, tail the boot log until the
# health check passes. ops/fly-setup.sh is the one-time version with app/db/secrets.
set -euo pipefail
backend="$(cd "$(dirname "$0")/.." && pwd)"
fly deploy "$backend" --config "$backend/fly.toml" --app slice-api
fly status --app slice-api
curl --fail --silent --show-error --max-time 10 https://slice-api.fly.dev/health
