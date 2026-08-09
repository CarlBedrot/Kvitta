# CLAUDE.md

## What this is

**Slice** — offline-first expense splitting app (Splitwise/Steven replacement). iOS native + .NET sync backend.
Renamed from Kvitta 2026-08-01: the *display* name, strings, icon and invite scheme say Slice; machine
identifiers (bundle id se.kvitta.app, defaults keys, package/module names, repo name) deliberately still
say kvitta — changing those wipes installed identities and belongs right before public release, if ever.
Full architecture: docs/expense-app-sync-design.md. Read it before touching sync, money, or event code.

## Repo layout

- ios/          SwiftUI app (App/). Project generated with XcodeGen (project.yml), gitignored. Never edit .xcodeproj directly; edit project.yml and regenerate.
- ios/Core/     Pure Swift package: events, projections, money, debt simplification. No UIKit/SwiftUI imports allowed here. Zero dependencies — keep it that way.
- ios/Storage/  GRDB event log, outbox, sync cursors, LedgerStore. The only place GRDB appears.
- ios/Sync/     The outbox/pull loop against the backend, behind a feature flag. The only package that knows a network exists.
- backend/      .NET 10 minimal API + Postgres 17, docker-compose for local deps.
- backend/Api/  The API project. EF Core migrations in backend/Api/Migrations.
- docs/         Design docs.

## Commands

- iOS generate project: xcodegen generate (run from ios/)
- iOS build: xcodebuild build -scheme App -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  (iPhone 17 Pro is on the iOS 26.5 runtime. Older sim names on this machine are iOS 18.2 and cannot install an iOS 26 app — the error you get is opaque.)
- Xcode tooling via MCP: prefer Apple's official bridge (xcrun mcpbridge, Xcode 26.3+); XcodeBuildMCP as fallback for simulator automation it does not cover
- App icon: the source of truth is docs/brand/slice-mascot.png — Carl's brand artwork, not generated. To regenerate the icon from it: copy to ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png, `sips -c 1024 1024` (center crop), then strip alpha via a jpeg round-trip (`sips -s format jpeg … && sips -s format png …`; the marketing icon must be opaque and exactly 1024×1024). The old SVG pipeline (tools/rasterize-icon.swift) is retired but kept for reference.
- Core package tests: swift test (from ios/Core/)
- Storage package tests: swift test (from ios/Storage/)
- Sync package tests: swift test (from ios/Sync/)
- App store tests: xcodebuild test -scheme AppTests -destination "platform=iOS Simulator,name=iPhone 17 Pro" (device-local stores; TEST_HOST is pinned in project.yml because PRODUCT_NAME is Kvitta, not App)
- Performance tests: swift test -c release. Debug builds are ~5x slower and say nothing about a shipped app.
- Backend run: dotnet run --project backend/Api (serves http://0.0.0.0:5142; the port and host are pinned in launchSettings.json because it overrides ASPNETCORE_URLS)
  The bind address is `0.0.0.0`, not `localhost`, so a sideloaded build on a friend's phone can reach the dev backend at `http://<your-mac-ip>:5142` over the same Wi-Fi. With `localhost` the socket only listens on loopback and every friend's phone gets connection refused while your own simulator works perfectly — a failure that looks like the app and is the server. This is a *development* convenience and the reason it is safe enough: the machine is a laptop on a home network, the dev sign-in endpoint mints tokens for any user id, and nothing here belongs on a public network. A real deploy is https behind a host and does not use this file.
- Backend first run on a machine: dotnet user-secrets set "Auth:SigningKey" "$(openssl rand -base64 48)" --project backend/Api
  There is no signing key in any committed file and the host refuses to start without one. That is deliberate — a checked-in key is a backdoor — so a fresh clone must do this once.
- Backend tests: dotnet test (from backend/; Testcontainers spins up postgres:17, so a container runtime must be running. KVITTA_TEST_POSTGRES overrides with a connection string if not.)
- Backend local deps: colima start, then docker compose up -d (from backend/)
- Database backup: backend/ops/backup.sh (writes backend/backups/, gitignored — real user data)
- Dev test data: python3 backend/ops/seed-dev.py --user <device-user-uuid> — fake friends with Swish numbers, three groups (one mixed SEK/DKK) via the real API. The uuid is `se.kvitta.localUserId` in the app's defaults (`xcrun simctl spawn booted defaults read se.kvitta.app`).
- Verify a backup: backend/ops/verify-restore.sh. Restores into a scratch database and checks row counts plus gap-free serverSeq. Run it on a schedule: a backup nobody has restored is a hypothesis, and the failure mode is silent.

## Non-negotiable rules

Money:
- All amounts are integer minor units (öre/øre). Never Double/Float/float/double for money. Int64 in Swift, long/decimal in C#, bigint in Postgres.
- Every expense must satisfy: sum(payers) == sum(shares) == amountMinor. Validate on write, client and server.
- Rounding happens once, at expense creation, deterministically (members sorted by memberId, remainder distributed from the top). Shares are stored resolved and never recomputed.

Events:
- Events are immutable. Corrections are new events (ExpenseUpdated with full payload), never edits to stored events.
- eventId is client-generated and is the idempotency key. serverSeq is server-assigned and is the only ordering that matters. clientTimestamp is display only.
- Projections must be pure functions (state, event) -> state. No side effects, no IO.
- Unknown event types and unknown payload fields must be skipped/tolerated, never crash.

Sync:
- Push responses are per-event: {accepted, rejected}. An all-or-nothing batch would let one bad event sit at the head of the outbox blocking every good event behind it forever.
- The server accepts event types it does not know, with envelope validation only, and stores them verbatim. It is a fan-out layer; rejecting would make every new event type a server deploy that must precede any client emitting one, and an unknown type moves no money because clients skip it when projecting.
- serverSeq is assigned under SELECT ... FOR UPDATE on the group row. A gap here is worse than a crash: the client cursor steps over it and an expense never arrives.
- A server rejection is not a transient failure. Rejected events leave the retry queue, stay in the log, and surface with their reason.
- The app must be fully functional with the backend unreachable. Any feature that requires a live server connection to add or view data is a design bug.
- Push is retry-safe because it is idempotent. Never drop outbox events silently; surface sync failures to the user.

Auth (M4a):
- Identity comes from the `sub` claim of a token this server signed. There is no trusted header; `X-Kvitta-User-Id` is gone.
- A `users` row is only ever created by POST /api/v1/auth/apple. Nothing else may mint one, which is why `MemberAdded.linkedUserId` must be null or the caller — linking somebody else is what invites are for, decided server-side.
- An event's `authorId` must equal the caller, rejected per-event as `author_mismatch`. Never a 403 for the whole batch: a batch is an outbox drain.
- Membership is decided in exactly one place, `Data/Membership.cs`, and includes `IsActive`. It was written out three times before and all three copies forgot it, so a removed member kept full access.
- Use `AddAuthentication` + `UseAuthentication` only. Never `RequireAuthorization` on an event route: the authorization middleware challenges before the handler, and an old client with no token must get 426 Upgrade Required rather than 401.
- `MapInboundClaims = false`, or JwtBearer silently renames `sub` and every subject lookup comes back empty.
- Refresh tokens rotate through one conditional UPDATE, never read-then-write. Reusing a spent token revokes the whole family — which is why the client's `AuthTokenProvider` must single-flight its refreshes, or a burst of 401s makes the app log itself out.
- Signing in is optional. The app without an account is the offline app, and that must stay fully functional.

Invites (M4b):
- `MemberUpdated` attaches a user to a member who already exists (§5). Absent fields mean unchanged; there is deliberately no way to unlink, because detaching an account from a member with history would strand money against nobody.
- Linking never moves money. Expenses reference members, never users, which is what lets someone join months late and inherit a history that already balances. The property generator emits MemberUpdated so the zero-sum property covers it.
- `POST /api/v1/invites/{token}/accept` writes its event server-side. That is a deliberate exception to "clients author events" and the only way out of a chicken-and-egg: membership is derived from the log, so the event that makes you a member cannot be written by a member. `PushAuthorisation.AcceptedInvite` is the only way to skip the membership guard and the accept endpoint is its only caller.
- Invite links are `slice://invite/<token>` (old `kvitta://` links still open), a custom scheme rather than a universal link, because an https link needs an apple-app-site-association file on a host that does not exist until M6. Universal links are additive: the token format and the accept endpoint do not change.

Payments and reminders (M5):
- The app never moves money. Swish/MobilePay get a prefilled deep link; PaymentRecorded says the money moved elsewhere.
- PaymentRecorded is pre-staged and only written when the user confirms on return. Opening Swish is not evidence a payment happened, and a phantom payment is worse than a missing one — the missing one is obvious.
- Amounts in a payment URL are built from integer minor units by hand. Never format money through a Double: 437.00 is not representable in binary floating point.
- A Swish number is never an event. Events are immutable, so a phone number in the log would reach every member forever with no way to take it back. It syncs as a *mutable server profile field* instead: `UserProfile.swishNumber` pushes to `PUT /me/profile` (`ProfileSyncer`, dirty-checked), co-members' numbers come down via `GET /groups/{id}/payees` into `PayeeDirectory` — the same device-local directory the settle-up sheet always read, so fetched and hand-typed numbers behave identically and the manual alert stays as the offline/unlinked fallback. Numbers are only served to group co-members, and clearing the field in Jag withdraws it.
- Reminders are local notifications computed from the ledger on device, so they need no network and no account. Only debts you owe — never money owed to you, which would be nagging someone else through your phone.
- Blocked on a paid Apple Developer team: Sign in with Apple (com.apple.developer.applesignin) and APNs silent push (aps-environment). Both are written or seamed but cannot be enabled or verified.
- A Swish payee is `46701234567` — country code, no trunk zero. `SwishNumber.normalised` is the only place that decides this; passing on whatever digits somebody typed is what got the first on-device attempt rejected as *"felaktigt format"*.
- The link we lead with is `swish://payment?data=<json>` (`PaymentLinkBuilder.swishAppSwitch`, callback nil), **verified on a real phone 2026-07**. Payee must be a *quoted* JSON string with country code (`"payee":{"value":"46701234567"}`). The `https://app.swish.nu/1/p/sw/?sw=…` universal link and an *unquoted* payee number were both rejected as *"felaktigt format"* — `swish(payee:amount:message:)` still builds the app.swish.nu shape but only the debug tester calls it.
- No `callbackurl`. Both callback and no-callback opened Swish fine on the phone, so this is a design choice, not a format constraint: returning is read from the scene phase, and the callback is what made Swish ask "open Kvitta?" on the way out, which reads like the app wants something.
- The simulator has no Swish app, so `canOpenURL` is always false and `openURL` always fails there — the format could only be settled on a device. `JagView` has a DEBUG-only "Testa Swish-format" that opens every candidate against 1,00 kr; that is how the shape above was found and is where any future format question gets re-tested.

Group photos:
- The group picture is a *mutable server field* (`groups.PhotoJpeg`; PUT/GET/DELETE `/groups/{id}/photo`), never an event — same reason as Swish numbers: a photo in the immutable log could never be taken back. Any member may set, replace or delete it; only members are served it; last write wins.
- 1 MB server cap, content-addressed ETag (quoted SHA-256 hex — `GroupPhotoSyncer.etag(of:)` computes the same tag client-side so a fresh push never re-downloads itself). `GroupImageStore` is the offline cache every screen reads; `GroupPhotoSyncer` pushes dirty picks and refreshes on group open. Offline picks stay dirty and retry.
- Photos are stored *uncropped*, downscaled to ≤1200 px with renderer scale 1 — `UIGraphicsImageRenderer`'s default screen scale silently tripled the pixels and produced ~2 MB uploads the cap refused. The banner crops at draw time; `GroupPhotoViewer` (tap the banner) shows the whole image.

Two-sided settle-up (M8):
- `PaymentRecorded` alone no longer moves money when the payee could ever object: it is born *pending* unless the payee has no linked account (the never-installs friend — nobody to ask) or recorded it themselves (their own confirmation). `PaymentConfirmed`/`PaymentDisputed`, keyed to the same PaymentID, resolve it; only the payee's `authorId` is accepted and anyone else's answer is skipped in projection as `notThePayee` — the projector replaying that guard on every device is the security boundary, not the server.
- **The never-confirms decision: auto-confirm after 7 days** (`PaymentStatus.autoConfirmAfterDays`). Computed at query time from the payment's own date — `balances(asOf:)` — so the fold stays pure; a stuck-forever debt punishes the honest payer for the payee's inattention, and the pending week is visible to everyone with a nudge (`ReminderPlanner.awaitingMyConfirmation`). A dispute beats the clock.
- The server needed no changes: `PaymentConfirmed`/`PaymentDisputed` are exactly the unknown-event-type path it was designed to fan out verbatim. Build 3 is the floor (`MinimumClientBuild: 3`) because a build-2 client would show one-sided balances from the same log.

Multi-currency (M7):
- An expense is exactly one currency — payers, shares and total all in `ExpensePayload.currency`. The *group* is the thing that mixes: `balances()` returns per-currency buckets (`GroupBalances`), each independently zero-sum, and buckets never net against each other. A SEK debt is paid in SEK.
- `GroupCreated.currency` is the group's *primary* currency: the default for new expenses and the ≈-conversion target. `GroupUpdated` may only change it while the ledger is empty — after that the field is ignored on both client and server, because relabelling stored amounts moves real money.
- Conversion is display-only and never stored. Rates are ECB's daily fixing, fetched as *decimal strings* from `eurofxref-daily.xml` (chosen over any JSON API precisely because JSON numbers arrive as Doubles) and parsed by string/integer math into micro-units (`ExchangeRates.micro(parsing:)`). All conversion is Int64; converted amounts are marked ≈ in the UI. `ECBRateClient` lives in ios/Sync because it is a network call.
- The server validates currency *shape* (three uppercase ASCII letters), not equality with the group. `currency_mismatch` is retired but the constant stays for old logs.
- Build 2 is the multi-currency floor: a build-1 client would skip foreign-currency events and show wrong balances, so `MinimumClientBuild` is 2. Bump both together or not at all.
- MobilePay (DKK transfers) opens the app with the exact amount on the clipboard — there is no public person-to-person prefill, and inventing one would be a button that lies.

Shipping (M6):
- Blocked on a paid Apple Developer account: TestFlight, App Store Connect, Sign in with Apple, APNs. Sorting the account out unblocks all four at once.
- Blocked on decisions that are Carl's to make, not a script's: choosing a host and deploying, creating a Sentry account, wiring an uptime monitor. The Dockerfile builds the artefact; nothing deploys it.
- backend/backups/ is gitignored. Never commit a dump — it is the friend group's real money history.
- PrivacyInfo.xcprivacy is required for App Store submission and declares no tracking, because there is none: no analytics SDK, no ad identifier, no third party.

Storage:
- Projections are held in memory and rebuilt from the log at launch, not cached in the database. A heavy group replays in ~20ms (ReplayPerformanceTests), so a second copy of the truth would buy nothing and could drift from the first.
- Write events only through LedgerStore.record. It appends to the log and folds into the projection in one call; there is deliberately no API to do either alone.
- rebuild() is what launch calls, so the recovery hatch is exercised every time the app opens instead of never.

SwiftUI:
- The app is light-only: INFOPLIST_KEY_UIUserInterfaceStyle in project.yml plus preferredColorScheme(.light) in KvittaApp. Theme is a fixed cream palette with no dark half, and every system-drawn label follows the system appearance — so without this a phone in dark mode gets white text on a cream card. Adding a dark palette is a design exercise; until it happens, do not remove either line.
- A group is created with only you in it. Names are never typed for other people at creation — they join by link and pick their own. `MembersSheet` still adds someone by name, for the friend who will never install the app (design doc §5), and that must not be removed.
- Never use AnyView to silence type-erasure errors. Use a @ViewBuilder generic or a switch over an enum returning concrete views. AnyView breaks SwiftUI diffing.
- Views over ~60 lines get split into subviews.
- Fast TDD loop: swift test --filter <TestName> from ios/Core/ for sub-second feedback; run the full suite before declaring a feature done.

Backend (.NET):
- Config via IOptions<T> or IConfiguration through DI. Never Environment.GetEnvironmentVariable().
- Server validates everything it stores (envelope + money invariant + membership). Trust nothing from clients. The one deliberate exception is payloads of event types the server does not know: those get envelope validation only, for the reason under Sync above.

## Testing policy

Money and projection logic requires property tests, not just examples:
1. Balances in a group always sum to exactly zero after any valid event sequence.
2. Same expense input always produces identical shares (rounding determinism).
3. Pushing the same event batch twice changes nothing.
4. Applying suggested settle-up transfers as payments zeroes all balances.
A PR touching ios/Core or backend event handling without tests is incomplete.

## Workflow

- New features: plan first (Plan mode), reference the design doc section, then build.
- When a PR is green, squash-merge it directly (delete the branch) without asking. Never end on "next step: merge it".
- Tool split: terminal Claude Code for ios/Core and backend/ (test-driven logic). In-Xcode Claude Agent (Xcode 26.3+) for SwiftUI screens, where Preview capture lets it verify UI visually.
- Keep ios/Core free of dependencies. It should compile on any platform.
- Prefer boring solutions. The project exists because clever backends go down.
