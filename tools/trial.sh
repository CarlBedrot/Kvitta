#!/usr/bin/env bash
#
# Takes the friend-phone trial from cold to "the phone can reach the server".
#
# The sequence this replaces lived in three places that never mentioned each other — the bind
# address in launchSettings.json, the dev-token flag in appsettings.Development.json, and the
# trust dance in iOS Settings — so getting it right meant remembering all three. It was run five
# times across three sessions and cost roughly twenty-five messages every time. This script is
# now the only thing that has to know.
#
#   ./tools/trial.sh
#
# Ends with the server in the foreground: Ctrl-C stops it. Postgres is deliberately left running,
# because the trial data lives in it and stopping it between runs would throw the ledger away.

set -euo pipefail

readonly PORT=5142
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

# Escape codes only when stdout is a terminal, so piping to a file doesn't fill it with garbage.
if [ -t 1 ]; then
    readonly BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m' RESET=$'\033[0m'
else
    readonly BOLD='' DIM='' RED='' GREEN='' RESET=''
fi

die() {
    printf '\n%serror:%s %s\n\n' "$RED$BOLD" "$RESET" "$1" >&2
    [ $# -gt 1 ] && printf '%s\n\n' "$2" >&2
    exit 1
}

step() { printf '%s▸ %s%s\n' "$BOLD" "$1" "$RESET"; }

# The address other devices reach this Mac on. Read at run time and never hard-coded: the router
# hands out a new lease often enough that a written-down address is wrong more often than right,
# and the failure it produces on the phone is a silent timeout rather than an error.
lan_ip() {
    local iface ip
    for iface in en0 en1 en2; do
        ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
        if [ -n "$ip" ]; then
            printf '%s' "$ip"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Preflight — every one of these fails later and more confusingly than it does here
# ---------------------------------------------------------------------------

step "Kontrollerar förutsättningar"

command -v dotnet >/dev/null 2>&1 \
    || die "dotnet saknas." "Installera .NET 10 SDK: brew install --cask dotnet-sdk"

command -v xcodegen >/dev/null 2>&1 \
    || die "xcodegen saknas." "Installera det: brew install xcodegen"

# The Docker daemon here is colima, not Docker Desktop — `docker context ls` shows colima as the
# active context and no Docker.app exists. Naming the wrong one sends you looking for an
# application that isn't installed, which is exactly the twenty-minute detour this script exists
# to prevent. Start it rather than only complaining: it takes about a minute and there is no
# decision in it.
if ! docker info >/dev/null 2>&1; then
    command -v colima >/dev/null 2>&1 \
        || die "Docker-daemonen svarar inte och colima saknas." \
               "Installera den: brew install colima"

    printf '%s  colima ligger nere — startar den (tar ~1 min)%s\n' "$DIM" "$RESET"
    colima start >/dev/null 2>&1 \
        || die "colima ville inte starta." "Kör 'colima start' för hand och läs felet."

    docker info >/dev/null 2>&1 \
        || die "colima startade men Docker svarar fortfarande inte." \
               "Kontrollera aktivt context: docker context ls"
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "Port $PORT är redan upptagen — förmodligen en backend som redan körs." \
"Se vad det är, och avsluta den:

    lsof -nP -iTCP:$PORT -sTCP:LISTEN

Kör den redan i lan-profilen behöver du inte det här skriptet alls."
fi

IP="$(lan_ip)" || die "Hittade ingen LAN-adress på en0/en1/en2." \
"Macen verkar inte vara på något nätverk. Anslut till ditt wifi och kör om.
Telefonen måste sedan vara på samma nät — mobildata når inte hit."

# ---------------------------------------------------------------------------
# Postgres
# ---------------------------------------------------------------------------

step "Startar Postgres"

docker compose -f "$ROOT/backend/docker-compose.yml" up -d >/dev/null

# `dotnet run` immediately after `up -d` races the first connection, so wait for the healthcheck
# the compose file already defines rather than sleeping a guessed number of seconds.
printf '%s  väntar på att den ska svara' "$DIM"
for _ in $(seq 1 30); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' kvitta-postgres 2>/dev/null)" = "healthy" ]; then
        printf ' klar%s\n' "$RESET"
        break
    fi
    printf '.'
    sleep 1
done
printf '%s' "$RESET"

[ "$(docker inspect -f '{{.State.Health.Status}}' kvitta-postgres 2>/dev/null)" = "healthy" ] \
    || die "Postgres blev aldrig frisk." "Titta på loggen: docker logs kvitta-postgres"

# ---------------------------------------------------------------------------
# Xcode — before the server, because the server runs in the foreground and never returns
# ---------------------------------------------------------------------------

step "Genererar Xcode-projektet"
( cd "$ROOT/ios" && xcodegen generate --quiet )
open "$ROOT/ios/Kvitta.xcodeproj"

# ---------------------------------------------------------------------------
# What the human has to do
# ---------------------------------------------------------------------------

cat <<EOF

${BOLD}Serveradressen att knappa in i appen${RESET}

    ${GREEN}${BOLD}http://${IP}:${PORT}${RESET}

    Jag → Serveradress → klistra in den → Jag → Logga in

${BOLD}I Xcode, som just öppnades${RESET}

    1. Välj din iPhone i destinations-dropdownen högst upp
    2. ⌘R

    Första körningen failar på telefonen med "Ej betrodd utvecklare".
    Då: Inställningar → Allmänt → VPN och enhetshantering → ditt Apple-ID → Lita på.
    Sedan ⌘R igen.

    ${DIM}Telefonen måste vara på iOS 26 eller nyare, och på samma wifi som den här Macen.
    Appen slutar fungera efter 7 dagar på gratissignering — kör om ⌘R för att förnya.${RESET}

${BOLD}Servern startar nu. Ctrl-C stoppar den.${RESET}
${DIM}Postgres lämnas igång med flit — trial-datan bor i den.${RESET}

EOF

# exec, so this script is replaced by the server rather than sitting above it as a parent that
# would have to forward signals. Note that `dotnet run` still starts the actual Kvitta.Api binary
# as a child: Ctrl-C works because the terminal signals the whole foreground process group, not
# because the signal is forwarded down. Verified — the port is released and no process is left
# behind. Sending SIGINT to this pid alone (as a script might) leaves the server running.
#
# Watch the first lines of output: the server says out loud which mode it is in, and
# "reachable from the network" is the one that means the phone can get in.
exec dotnet run --project "$ROOT/backend/Api" --launch-profile lan
