# CLAUDE.md

## What this is

Offline-first expense splitting app (Splitwise/Steven replacement). iOS native + .NET sync backend.
Full architecture: docs/expense-app-sync-design.md. Read it before touching sync, money, or event code.

## Repo layout

- ios/          SwiftUI app. Project generated with XcodeGen (project.yml). Never edit .xcodeproj directly; edit project.yml and regenerate.
- ios/Core/     Pure Swift package: events, projections, money, debt simplification. No UIKit/SwiftUI imports allowed here.
- backend/      .NET 10 minimal API + Postgres. EF Core migrations in backend/Migrations.
- docs/         Design docs.

## Commands

- iOS generate project: xcodegen generate (run from ios/)
- iOS tests: xcodebuild test -scheme App -destination "platform=iOS Simulator,name=iPhone 16"
  (TODO: pin this to the exact simulator on this machine after first build; a wrong destination string gives opaque errors)
- Xcode tooling via MCP: prefer Apple's official bridge (xcrun mcpbridge, Xcode 26.3+); XcodeBuildMCP as fallback for simulator automation it does not cover
- Core package tests only: swift test (from ios/Core/)
- Backend run: dotnet run --project backend/Api
- Backend tests: dotnet test
- Backend local deps: docker compose up -d (Postgres)

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
- The app must be fully functional with the backend unreachable. Any feature that requires a live server connection to add or view data is a design bug.
- Push is retry-safe because it is idempotent. Never drop outbox events silently; surface sync failures to the user.

SwiftUI:
- Never use AnyView to silence type-erasure errors. Use a @ViewBuilder generic or a switch over an enum returning concrete views. AnyView breaks SwiftUI diffing.
- Views over ~60 lines get split into subviews.
- Fast TDD loop: swift test --filter <TestName> from ios/Core/ for sub-second feedback; run the full suite before declaring a feature done.

Backend (.NET):
- Config via IOptions<T> or IConfiguration through DI. Never Environment.GetEnvironmentVariable().
- Server validates everything it stores (schema + money invariant + membership). Trust nothing from clients.

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
