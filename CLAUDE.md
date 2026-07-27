# CLAUDE.md

## What this is

Offline-first expense splitting app (Splitwise/Steven replacement). iOS native + .NET sync backend.
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
- App icon: the source of truth is docs/brand/kvitta-app-icon.svg. Never edit AppIcon.png; edit the SVG and regenerate:
  swiftc -O tools/rasterize-icon.swift -o /tmp/rasterize-icon &&
  /tmp/rasterize-icon docs/brand/kvitta-app-icon.svg ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png 1024
  (compile it — `swift tools/rasterize-icon.swift` runs the interpreter, which takes minutes to load AppKit and looks like a hang)
- Core package tests: swift test (from ios/Core/)
- Storage package tests: swift test (from ios/Storage/)
- Sync package tests: swift test (from ios/Sync/)
- Performance tests: swift test -c release. Debug builds are ~5x slower and say nothing about a shipped app.
- Backend run: dotnet run --project backend/Api (serves http://localhost:5142; the port is pinned in launchSettings.json because it overrides ASPNETCORE_URLS)
- Backend first run on a machine: dotnet user-secrets set "Auth:SigningKey" "$(openssl rand -base64 48)" --project backend/Api
  There is no signing key in any committed file and the host refuses to start without one. That is deliberate — a checked-in key is a backdoor — so a fresh clone must do this once.
- Backend tests: dotnet test (from backend/; Testcontainers spins up postgres:17, so a container runtime must be running. KVITTA_TEST_POSTGRES overrides with a connection string if not.)
- Backend local deps: colima start, then docker compose up -d (from backend/)

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
- Invite links are `kvitta://invite/<token>`, a custom scheme rather than a universal link, because an https link needs an apple-app-site-association file on a host that does not exist until M6. Universal links are additive: the token format and the accept endpoint do not change.

Payments and reminders (M5):
- The app never moves money. Swish/MobilePay get a prefilled deep link; PaymentRecorded says the money moved elsewhere.
- PaymentRecorded is pre-staged and only written when the user confirms on return. Opening Swish is not evidence a payment happened, and a phantom payment is worse than a missing one — the missing one is obvious.
- Amounts in a payment URL are built from integer minor units by hand. Never format money through a Double: 437.00 is not representable in binary floating point.
- A payee's Swish number lives in UserDefaults on the device, never as an event. Events are immutable, so a phone number in the log would reach every member forever with no way to take it back.
- Reminders are local notifications computed from the ledger on device, so they need no network and no account. Only debts you owe — never money owed to you, which would be nagging someone else through your phone.
- Blocked on a paid Apple Developer team: Sign in with Apple (com.apple.developer.applesignin) and APNs silent push (aps-environment). Both are written or seamed but cannot be enabled or verified.
- Unverified: the Swish payload format. The simulator has no Swish app so canOpenURL is always false there; it needs one check on a real phone before shipping.

Storage:
- Projections are held in memory and rebuilt from the log at launch, not cached in the database. A heavy group replays in ~20ms (ReplayPerformanceTests), so a second copy of the truth would buy nothing and could drift from the first.
- Write events only through LedgerStore.record. It appends to the log and folds into the projection in one call; there is deliberately no API to do either alone.
- rebuild() is what launch calls, so the recovery hatch is exercised every time the app opens instead of never.

SwiftUI:
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
- Tool split: terminal Claude Code for ios/Core and backend/ (test-driven logic). In-Xcode Claude Agent (Xcode 26.3+) for SwiftUI screens, where Preview capture lets it verify UI visually.
- Keep ios/Core free of dependencies. It should compile on any platform.
- Prefer boring solutions. The project exists because clever backends go down.
