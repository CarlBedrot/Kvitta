# Expense App: Data Model & Sync Protocol Design

Design goal: the app is fully functional offline. The backend is a dumb, boring sync and fan-out layer. If the server is down, users can still add expenses, see balances, and settle up. Sync catches up later. This is the property Steven and Splitwise lack.

## 1. Core idea: per-group event log

Every mutation is an immutable event appended to a per-group stream. Balances, expense lists, and edit history are all projections derived from the log. The log is the source of truth; projections are caches.

Why this shape:

- Merging offline work is append, not merge. No three-way diffs.
- Edit history and undelete fall out for free (Splitwise sells both as features).
- Server logic is trivial: validate, assign sequence number, store, fan out. Little to break.

## 2. Event envelope

```json
{
  "eventId": "uuid, client-generated, idempotency key",
  "groupId": "uuid",
  "entityId": "uuid of the expense/payment/member this concerns",
  "type": "ExpenseCreated",
  "schemaVersion": 1,
  "authorId": "uuid",
  "clientTimestamp": "2026-07-22T18:30:00Z",
  "serverSeq": 4711,
  "payload": { }
}
```

- eventId: generated on device. Unique constraint server-side makes retries idempotent.
- serverSeq: assigned by the server, strictly monotonic per group. This is the total order everyone agrees on and the sync cursor.
- clientTimestamp: display only (when did Carl actually add this). Never used for ordering.

### Event types (MVP)

| Type | entityId | Notes |
|---|---|---|
| GroupCreated / GroupUpdated | groupId | name, currency, cover photo |
| MemberAdded / MemberRemoved | memberId | see placeholder members, section 5 |
| ExpenseCreated | expenseId | full payload |
| ExpenseUpdated | expenseId | full replacement payload, not a diff |
| ExpenseDeleted / ExpenseRestored | expenseId | soft delete |
| PaymentRecorded | paymentId | settle-up, incl. method: cash, swish, mobilepay |
| CommentAdded | commentId | v1.1 |

ExpenseUpdated carries the complete new expense. Last event in serverSeq order wins entirely. No per-field merging. For a two-person edit race on the same expense (rare in practice) the later sync wins and the earlier version is still visible in history. This is exactly how Splitwise behaves and nobody complains.

## 3. Expense payload and the money rules

```json
{
  "description": "Systembolaget",
  "categoryId": "groceries",
  "date": "2026-07-21",
  "currency": "SEK",
  "amountMinor": 43700,
  "payers":  [ { "memberId": "m1", "amountMinor": 43700 } ],
  "shares":  [ { "memberId": "m1", "amountMinor": 14567 },
               { "memberId": "m2", "amountMinor": 14567 },
               { "memberId": "m3", "amountMinor": 14566 } ],
  "splitMethod": "equal",
  "splitInput": { }
}
```

Hard rules:

1. All amounts are integer minor units (öre/øre). Int on device, bigint in Postgres. Floats never touch money.
2. Invariant: sum(payers) == sum(shares) == amountMinor. Enforced on device at save time and revalidated by the server on ingest. An event violating it is rejected.
3. Rounding is resolved at write time, on the device that creates the event. 437.00 / 3 becomes 145.67 + 145.67 + 145.66. Remainder öre are assigned deterministically: sort members by memberId, distribute leftover from the top. Everyone who replays the log computes identical balances because shares are stored resolved, never recomputed.
4. splitMethod + splitInput exist only so the UI can reopen the split editor in the same mode (percentages, shares, exact). They are never used for balance math.

## 4. Projections

### Balances

Fold over the log: each expense credits payers and debits share-holders; each PaymentRecorded moves balance from payer to recipient. Net balance per member per group. Sum across a group is always exactly zero. Write a property test for this on both platforms; it is the single most valuable test in the codebase.

### Debt simplification

Run on the derived balances, purely client-side, display only (it never creates events):

1. Split members into debtors and creditors.
2. Repeatedly match largest debtor against largest creditor, transfer min of the two, repeat.

Gives at most n-1 suggested transfers. Deterministic if ties break on memberId.

### Storage of projections

- Device: SwiftData models (Group, Member, Expense, BalanceCache) rebuilt incrementally as events apply. Full rebuild from the local log is a debug menu item and your recovery hatch.
- Server: for MVP, none. The server serves events; it does not need to understand balances. Add a server-side balance projection later only if you build a web view or want server-computed notifications ("you owe 240 kr").

The projection logic (apply event to state) exists twice, Swift and C#, once the server needs it. Until then it exists once. Keep it a pure function state -> event -> state so it stays testable and portable.

## 5. Members vs users: placeholder members

The single most important UX decision in this category: you must be able to split with people who never install the app.

- A Member is a row in a group: memberId, displayName, optional linkedUserId.
- Adding your friend Jonas who cannot be bothered to sign up: MemberAdded with linkedUserId = null. Expenses reference memberId, so everything works.
- If Jonas later joins via invite link, a MemberUpdated event sets linkedUserId. His device then syncs the full group history and his balances appear. No expense rewriting needed because expenses never referenced users directly.

This indirection (expenses -> members -> optionally users) is cheap now and impossible to retrofit later.

## 6. Sync protocol

### Client state per group

- cursor: highest serverSeq applied locally
- outbox: ordered queue of locally created events not yet acknowledged

### Push

```
POST /groups/{id}/events
Body: [ event, event, ... ]        (outbox batch, client order)
200:  [ { eventId, serverSeq }, ... ]
```

Server: authenticate, check membership, validate schema + money invariant, insert with next serverSeq per group (unique index on eventId makes duplicates a no-op returning the existing seq). Ack removes events from the outbox. Any network failure: keep in outbox, retry with backoff. Safe because idempotent.

### Pull

```
GET /groups/{id}/events?after={cursor}&limit=500
200: { "events": [ ... ], "nextCursor": 4711 }
```

Apply in serverSeq order, advance cursor. Repeat until empty page.

### Ordering subtlety

Local events apply to the UI immediately (optimistic). When the same event returns from pull (it will, after push), it is skipped by eventId. If a pull delivers other members' events that interleave before your unacked local events, reapply projections in serverSeq order with outbox events appended last. In practice: rebuild the affected projections from the last few hundred events; at this data size that is microseconds, so do not build a clever patching system.

### Triggers

- App open / foreground: pull all groups (parallel), push outbox
- After any local mutation: push (debounced a few seconds)
- APNs silent push (content-available) with groupId when another member pushes events: targeted pull. Silent pushes are best-effort and throttled by iOS, so they accelerate sync but must never be required for correctness. Foreground pull is the guarantee.

### New device / reinstall

Pull each group from cursor 0 and replay. A heavy group with 5,000 events is still well under a second of replay on-device. Skip server snapshots for MVP; add GET /groups/{id}/snapshot later only if replay ever measurably hurts.

## 7. Auth, invites, permissions

- Sign in with Apple as the only login for MVP. Server verifies the identity token, issues its own short-lived JWT + refresh token.
- Invite: POST /groups/{id}/invites returns a token URL (universal link). Accepting it creates or links a Member. Tokens expire and are revocable.
- Authorization: every event route checks current membership. A removed member can no longer push or pull. Edge case: their unsynced offline events are rejected on push; the client surfaces "these expenses could not sync" rather than silently dropping them.

## 8. Server data model (Postgres)

```sql
users        (id uuid pk, apple_sub text unique, display_name text, created_at timestamptz)
groups       (id uuid pk, created_at timestamptz)
members      (id uuid pk, group_id uuid fk, linked_user_id uuid null fk, display_name text)
invites      (token uuid pk, group_id uuid fk, expires_at timestamptz, revoked bool)
events       (group_id uuid, server_seq bigint, event_id uuid unique,
              entity_id uuid, type text, schema_version int, author_id uuid,
              client_ts timestamptz, payload jsonb, received_at timestamptz,
              primary key (group_id, server_seq))
```

serverSeq assignment: max(server_seq) + 1 inside the insert transaction with the group row locked (SELECT FOR UPDATE on groups). At this write volume, per-group serialization is a non-issue and buys you a gap-free, strictly ordered stream, which keeps the client cursor logic trivial.

Group name, currency etc. live in the event log (GroupUpdated), not in columns; the groups table is just an anchor for locking and FK integrity.

## 9. Schema evolution

- schemaVersion on every event. Readers must tolerate unknown fields (Codable with defaults; System.Text.Json ignores extras by default).
- New event types: old clients skip unknown types during projection rather than crashing. Log a warning.
- Breaking change escape hatch: server can respond 426 Upgrade Required with a minimum build number; the app shows a forced-update screen. Build this in v1, you will want it exactly once and it will save you.

## 10. Testing priorities

1. Property test: after any sequence of valid events, group balances sum to zero. (Swift + C#)
2. Rounding determinism: same expense input always yields identical shares.
3. Sync round-trip: create offline on device A, sync, device B converges to identical projections.
4. Idempotency: pushing the same batch twice changes nothing.
5. Debt simplification: suggested transfers, when applied as payments, zero out all balances.

## 11. Deliberately out of scope for MVP

- Multi-currency conversion (currency per group only, no FX)
- Server-side projections and web client
- CRDTs or per-field merge logic (LWW per expense is enough)
- Snapshots/compaction (the log is small and is the history feature)
- Real payment APIs (Swish/MobilePay deep links + PaymentRecorded events instead)
