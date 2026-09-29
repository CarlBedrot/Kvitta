# Slice: small-scale release gate

Status checked **2026-09-29**. The current service is a hosted trial, not yet a production release.
Working scope: a small invited group; public App Store distribution is a separate gate.
Tracker: [#68](https://github.com/CarlBedrot/Kvitta/issues/68).

## What is verified

- Redesign merged in #117. Core, Sync and app tests passed; simulator expense creation,
  cross-currency balances and settlement were exercised. This is not two-device or Swish QA.
- Fly API `slice-api`, one 512 MB shared-CPU machine in Stockholm, is running over HTTPS.
- Database `slice-db`, database name `slice_api`, runs Postgres 18. One encrypted 1 GB volume;
  automatic daily snapshots enabled, retention five days, five snapshots present at audit time.
- A fresh hosted logical dump was restored into an isolated local Postgres 18 database on
  2026-09-29. All six required tables restored; event sequences were contiguous in every group.
  Only counts/integrity were inspected. This did not test restoring a Fly volume or switching traffic.
- Backend tests cover database-aware readiness and independent liveness. CI runs backend tests
  and backup/restore checks on Postgres 17 and 18, plus the existing Swift Core tests.

## Required before real users rely on it

| Gate | Remaining work / evidence |
|---|---|
| Real identity | Hosted `Auth__AllowDevTokens=true` and the bundled shared trial key permit callers to select a trial user ID. A shared key does not prove which user is calling. Enable Sign in with Apple (provider/backend already exist), verify paid team/entitlements (#44), and retire the trial route/key. |
| Existing accounts | Specify and test how each existing trial identity, membership, offline event and debt survives the switch to Apple. Do not simply replace the provider and strand old data. Do not treat possession of the shared trial key as proof of account ownership. |
| Operational alerts | Sentry hooks exist but no backend DSN secret or iOS DSN is configured. Configure projects and an alert recipient; verify a scrubbed test error is received. Configure an external monitor of `/health` and prove its failure/recovery notifications arrive. Fly health checks alone do not establish this. |
| Recovery | Daily Fly snapshots allow a loss window of roughly a day. Decide whether that is acceptable. Rehearse restoring a snapshot into a separate Fly app and reconnecting a staging API; record elapsed recovery time. Keep an encrypted off-provider backup and a recurring restore check. The manual logical recovery test above is a first step. |
| Two real phones | #47/#48: install/relaunch; invite over mobile data; create/edit expenses; offline writes and later convergence; payer/payee confirmation and dispute; profile/Swish number sync; real Swish handoff; group photos. Check upgrade/reinstall/account recovery without losing the ledger. |
| Distribution | Confirm paid Apple team and TestFlight signing. Verify the actual release build on devices, large text and VoiceOver. Before public App Store release, finish the privacy/support page, accurate store privacy disclosures, and an account-deletion design consistent with shared ledger history. |

APNs push and extra server replicas are not prerequisites for this small invited release.
Foreground sync must work reliably. The one-node database has downtime risk; it is not highly
available. Fly describes this database product as [unmanaged and no longer maintained](https://docs.fly.io/unmanaged-postgres/managing/backup-and-restore).
Keep its maintenance/recovery responsibility explicit, or choose managed Postgres before expanding.

## Health and deploy

- `/health`: no authentication; returns 200 only if Postgres accepts a connection, otherwise 503.
  It does not validate every table or a user flow. Dependency check deadline: three seconds.
- `/health/live`: process-only liveness. Both responses are uncached and contain no diagnostics.
- `backend/ops/fly-deploy.sh` builds from the backend directory, waits for Fly's rolling health
  check and verifies the public readiness URL. Run only from reviewed, green source.
- Record the prior image with `fly image show --app slice-api` before deploying. To roll code
  back, deploy that exact image using `fly deploy --app slice-api --image <prior-image>` with
  the backend config. Never roll back database migrations automatically; assess compatibility first.

## Hosted backup and isolated restore

Run `backend/ops/fly-backup.sh` from an authenticated Fly session. It streams a read-only
`pg_dump` through SSH into `backend/backups/` (gitignored), with mode 0600. The command must
succeed before the final archive is published. It does not schedule itself or prune old hosted
backups. Protect and retain these files as user data, including session-token hashes.

Verify with a dedicated local container; do not point a recovery rehearsal at the production DB:

```sh
docker run --detach --name slice-restore-check \
  --env POSTGRES_HOST_AUTH_METHOD=trust --env POSTGRES_USER=kvitta postgres:18
# Wait until this succeeds:
docker exec slice-restore-check pg_isready -U kvitta
KVITTA_PG_CONTAINER=slice-restore-check \
  backend/ops/verify-restore.sh backend/backups/<exact-backup-file>.sql.gz
docker rm --force --volumes slice-restore-check
```

The container publishes no ports. The check restores to a uniquely named scratch database,
requires every application table, checks per-group sequence integrity, and removes only its own
scratch database. A missing table or failed SQL command fails the check. It deliberately does not
compare with current live counts, which may have changed since the backup. It is not a checksum
proof of every field or a replacement for application-level recovery QA.

For snapshot recovery, use Fly's [restore procedure](https://docs.fly.io/unmanaged-postgres/managing/backup-and-restore)
with the recorded database image and snapshot ID. Restore into a **new** app first, validate it,
then plan a controlled connection switch. Preserve the existing database until recovery is verified.
