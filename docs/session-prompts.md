# Claude Code Session Prompts

Copy-paste per milestone. Run M1 first. Repo must contain CLAUDE.md and docs/expense-app-sync-design.md before starting.

---

## Session 1 (Milestone 1: Core package)

Read CLAUDE.md and docs/expense-app-sync-design.md fully before doing anything.

Enter plan mode and plan Milestone 1: a pure Swift package at ios/Core with no UI and no networking, containing:

1. Money type: integer minor units, currency code. No floating point anywhere.
2. Event model per the design doc section 2: envelope + payloads for ExpenseCreated, ExpenseUpdated, ExpenseDeleted, ExpenseRestored, PaymentRecorded, GroupCreated, GroupUpdated, MemberAdded, MemberRemoved. Codable, tolerant of unknown fields and unknown event types.
3. Split calculator: equal, exact, percentage, shares. Deterministic rounding per design doc section 3 (members sorted by memberId, remainder from the top). Output is resolved shares in minor units.
4. Projection: pure function (state, event) -> state producing groups, members, expenses, and balances. Per-group balances must sum to exactly zero.
5. Debt simplification: greedy largest-debtor/largest-creditor matching, deterministic tie-break on memberId, max n-1 transfers.

Acceptance criteria:
- swift test passes with the four property tests from CLAUDE.md testing policy implemented using swift-testing, with randomized event sequences (at least 1000 iterations each).
- Invariant sum(payers) == sum(shares) == amountMinor is enforced at construction; invalid expenses are unrepresentable or throw.
- Package has zero dependencies and compiles with swift build on macOS.

Do not scaffold the app target, backend, or persistence in this session. Show me the plan before building.

---

## Session 2 (Milestone 2: local-only app)

Read CLAUDE.md, docs/expense-app-sync-design.md sections 4-6, docs/ui-design.md, and open docs/mockup.html as the visual reference. Plan then build the local-only iOS app: GRDB event store (append-only events table, outbox table, per-group cursor table), projections persisted as GRDB records rebuilt from the log, and SwiftUI screens for group list, group detail with balances, add/edit expense with all split modes, settle up (record payment), and expense history. Placeholder members (no accounts) only. XcodeGen project.yml, min iOS 17. No networking. Acceptance: I can run it in the simulator, create a group, add expenses in every split mode, and balances match hand-calculated values. Debug menu item: rebuild projections from log.

---

## Session 3 (Milestone 3: sync backend)

Read CLAUDE.md and docs/expense-app-sync-design.md sections 6-8. Plan then build backend/: .NET 10 minimal API with the push and pull endpoints, Postgres schema per section 8, serverSeq assignment under group row lock, idempotency on eventId, validation of the money invariant and schema. Docker compose for local Postgres. Integration tests: idempotent double-push, ordered pull with cursor, invariant rejection. Then wire the iOS outbox/pull loop to it behind a feature flag.

---

## Session 4 (Milestone 4: auth + invites)

Sign in with Apple end to end (server verifies identity token, issues JWT + refresh), invite links (universal links), member linking per design doc section 5, membership authorization on every event route, rejected-event surfacing in the app.

---

## Session 5 (Milestone 5: push + settle-up links)

APNs silent push triggering targeted pull (best effort only, foreground pull remains the guarantee). Swish prefill deep link for SEK settle-up (base64 JSON prefill format, verify on device). MobilePay: copy-amount + open-app fallback, pre-staged PaymentRecorded confirmation on return. Payment reminders as local scheduling first.

---

## Session 6 (Milestone 6: TestFlight)

App icon, launch screen, privacy manifest, App Store Connect setup, TestFlight build, crash reporting (Sentry), backend deploy with health check + uptime monitor + automated Postgres backups with a tested restore.

---

## Product principles (paste into CLAUDE.md if not already there)

- Free forever for this friend group. No gating logic, no limits, no ads, no code paths for any of those.
- No bank sync, ever. It is the fragile dependency that killed Steven. Receipt photo parsing instead.
- Every balance must be auditable: tapping it shows the exact expenses and payments behind it. CSV export early.
- The app never holds or transfers money. Deep links to Swish/MobilePay only; money moves bank to bank.
