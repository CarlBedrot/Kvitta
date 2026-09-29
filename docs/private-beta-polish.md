# Private beta polish plan

Approved direction, 2026-09-29: a simple, readable Slice for Carl and his girlfriend before
public distribution. [Plan #119](https://github.com/CarlBedrot/Kvitta/issues/119) tracks delivery.

## Sequence and acceptance

1. **#120 — Balance priority:** put currencies with the current user's open debts first. Preserve
   gross directions when net is zero; never rank different currencies by their numeric amount.
   Overview and Position share the same ordering. Cover ordering, other users, settled/empty
   states and cross-group offsetting debts with regression and generated tests.
2. **#121 — Visual simplification:** one compact header, native scalable typography, one blue
   pizza brand mark on Overview, clear amounts and direction words. Remove slogans, repeated
   logos and explanatory captions that repeat the visible data. Keep the amount-first expense
   sheet and useful recovery/error text. Verify the main screens in light and dark appearances.
3. **#122 — Recent activity:** the overview must include relevant actions by the current user;
   the existing other-person news feed can retain its own explicit scope. Verify save/edit/delete
   and payment cases, deterministic ordering, and opening the correct detail.
4. **#123 — Layout and flow verification:** normal and accessibility text, narrow phone and iPad,
   light/dark, long names and large amounts, keyboard/tab-bar reachability, empty/offline/blocked
   states, VoiceOver and Reduce Motion. Record actual runtime evidence separately from source
   inspection, and fix concrete findings.
5. **#47 / #48 — Physical trial:** install without deleting existing data, exercise hosted sync on
   two phones including mobile data/offline convergence, invitation, settlement confirmation and
   dispute, real Swish, profile/photos, relaunch and final visual feedback.

## Boundaries

Preserve the blue pizza identity and five current navigation actions. No rebrand, new dashboard,
custom fonts, onboarding carousel, event migration, monetary calculation or authentication change.
Use Swedish and English. The source model remains the existing per-group ledger; see
`expense-app-sync-design.md` sections 3–5 and 10. Multi-currency rules in `CLAUDE.md` supersede
the original design's obsolete single-currency scope.

This direction supersedes the old warm/clay palette and three-tab layout described in
`ui-design.md`; the brand and navigation already shipped in #117 remain authoritative.

## Verification status

### First implementation batch — 2026-09-29 (#120/#121)

- Overview and Position now share personal open-balance ordering, with alphabetic currency
  order within open/settled buckets. Offset gross debts remain visible even when net is zero.
- Compact headers and semantic type replace repeated branding, greetings and slogans. Balance
  cards retain explicit currency and direction; settled currencies no longer show empty filters.
- Core: 134 tests passed, including fixed and 200-seed balance ordering cases. Sync: 31 passed
  on an isolated rerun; the existing debounce test initially failed its wall-clock deadline while
  other builds/tests were running. No sync code changed. Track that timing sensitivity in #123.
- Simulator AppTests: 30 passed, no skipped tests, on iPhone 17 Pro / iOS 26.5. App builds,
  installs and launches. Overview, Position, Groups and Profile inspected in light and dark
  appearances with synthetic data and sync disabled. The review case shows 257.99 SEK owed
  to the current user before settled DKK. Swedish and English balance labels checked.
- Local visual evidence: `/tmp/slice-polish-evidence/` (before/after overview and sampled
  secondary screens). These are local review artifacts, not device evidence.

Next: #122 recent activity, then the broader #123 runtime/accessibility matrix. Larger text,
narrow phone/iPad, VoiceOver, Reduce Motion and all recovery/mutation flows are not signed off
by this first visual pass. Physical phone results, real Swish and subjective approval remain
open; no simulator result closes #47 or #48. Public-release readiness continues separately in #68.
