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

Read CLAUDE.md, docs/expense-app-sync-design.md sections 4-6, docs/ui-design.md, and open docs/mockup.html as the visual reference. Plan then build the local-only iOS app: GRDB event store (append-only events table, outbox table, per-group cursor table), projections persisted as GRDB records rebuilt from the log, and SwiftUI screens for group list, group detail with balances, add/edit expense with all split modes, settle up (record payment), and expense history. Placeholder members (no accounts) only. XcodeGen project.yml, min iOS 26 (glass-native from day one, per docs/ui-design.md). No networking. Acceptance: I can run it in the simulator, create a group, add expenses in every split mode, and balances match hand-calculated values. Debug menu item: rebuild projections from log.

**Status: the data half is done and merged (PR #2).** One deviation from the above, accepted: projections are held in memory and rebuilt from the log at launch rather than persisted as GRDB records. A heavy group replays in ~20 ms, so a second copy of the truth would buy nothing and could drift from the first — and it makes launch and "rebuild projections" the same code path, so the recovery hatch runs constantly instead of never.

---

## Session 2b (Milestone 2: the screens) — run this in the **in-Xcode Claude Agent**

Terminal Claude Code stops at the data layer per CLAUDE.md's tool split; the screens want Preview capture to verify them visually. Open ios/Kvitta.xcodeproj (run `xcodegen generate` from ios/ first if it is missing — it is gitignored) and paste:

> Read CLAUDE.md, docs/ui-design.md, and open docs/mockup.html — it is authoritative for palette, layout and tone. Read ios/App/RootView.swift to see what exists and ios/Storage/Sources/KvittaStorage/LedgerStore.swift for the API you build against.
>
> The data layer is finished and tested (106 tests). Do not add persistence, networking, or money logic — all of it exists. In particular: never compute a split yourself, call `SplitCalculator.resolve`; never sum balances yourself, call `GroupState.balances()`; never write an event except through `LedgerStore.record`, which appends to the log and updates the projection in one call.
>
> Replace the placeholder RootView with the real screens from docs/ui-design.md §Screens, in this order: (1) Hem/Grupper with the Totalt card and the zero line, (2) Ny utgift as an amount-first sheet over a custom keypad with the split editor behind one summary row, (3) Gruppvy with simplified transfers and the expense list, (4) Balansgranskning — `GroupState.breakdown(for:)` already returns the lines with a running total that lands on exactly the displayed balance, (5) Gör upp, (6) Utgiftsdetalj with edit history from `Expense.revision`, (7) Aktivitet.
>
> Liquid Glass on the control layer only; content stays opaque. Never AnyView — use @ViewBuilder or a switch over an enum returning concrete views. Views over ~60 lines get split. Swedish and English from day one via String Catalog, Swedish is the reference copy. Amounts in SF Rounded with monospaced digits, and direction always in words next to the number so colour never carries meaning alone.
>
> Acceptance: create a group, add expenses in every split mode, and check the balances against hand-calculated values. 437.00 kr split three ways must read 145.67 / 145.67 / 145.66.

**Status: done (PR #4).** All seven screens built and verified on device; ios/Core and ios/Storage untouched. Acceptance held: 437 kr three ways reads 145,67/145,67/145,66 through the app's own path. Two accepted deviations, documented in code: Balansgranskning audits a member's balance against the group (what `breakdown(for:)` guarantees to the öre) rather than the mockup's pairwise sketch, and the suggestion chips render opaque because glass chips would exceed the three-glass-elements rule. Deliberately deferred: Swish/MobilePay deep links (M5), settle-collapse animation polish, CSV export + group toolbar (add member/settings), dark mode tuning, and unsynced-row badges (meaningless until M3). The Jag tab is a stub holding diagnostics and the debug seed/rebuild tools.

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

## Session 7 (Milestone 7: settle-ups the other person has to agree to)

From the first real-hardware test: *"if something is marked as approved, it can not be approved
totally until the other user gets a notification about it and he/she presses approved."*

Today `PaymentRecorded` is one-sided. Whoever taps "Markera som betald" moves the balance for
everybody, and the person who was supposed to receive the money finds out by noticing. For cash
between friends that is usually fine; for anything larger it is the one place the ledger can be
wrong and look right.

Shape, so the thinking is not lost:

- A new `PaymentConfirmed` event keyed to the same `PaymentID`. `PaymentRecorded` alone becomes
  *pending* and does not move the balance; the pair does.
- The payee sees pending payments on their next foreground pull and confirms or disputes. No APNs —
  still blocked on the paid Apple team — so `ReminderPlanner` carries the nudge, which it can
  already do with no network and no account.
- Projections stay pure `(state, event) -> state`. A pending payment is state, not a side channel.

**The decision that makes this a milestone and not a task: what happens when the other person never
confirms.** A debt stuck forever because someone stopped opening the app is worse than one settled
optimistically, and every answer (auto-confirm after N days, confirm-on-behalf, dispute-only) trades
a different thing away. Pick one before writing any of it.

`PropertyTests.swift` has to be extended first — a pending payment must not break the zero-sum
property, and "applying the suggested transfers as payments zeroes all balances" needs restating in
terms of confirmed payments.

---

## Product principles (paste into CLAUDE.md if not already there)

- Free forever for this friend group. No gating logic, no limits, no ads, no code paths for any of those.
- No bank sync, ever. It is the fragile dependency that killed Steven. Receipt photo parsing instead.
- Every balance must be auditable: tapping it shows the exact expenses and payments behind it. CSV export early.
- The app never holds or transfers money. Deep links to Swish/MobilePay only; money moves bank to bank.
