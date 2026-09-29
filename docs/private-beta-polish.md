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

### Composition revision — 2026-09-29

Carl's screenshot feedback supersedes the first pass's filled balance card: the overview still
looks like disconnected modules and its colours compete. Put balances on the page, remove the
overview's row containers and duplicate add button, and use neutral surfaces/placeholders with
one blue action accent. Keep currency/direction, offset gross debts, photos and all destinations.
Verify both appearances, large text and expense entry before merging; subjective approval and
the remaining #123/device gates stay open.

Implemented in #125: flat balance presentation, unboxed overview rows, neutral avatar/group
placeholders and one adaptive blue action pair. The phone navigation shares the page background;
its add button remains available and opens the existing expense flow. At accessibility sizes,
the activity heading stacks above its link. Navigation labels are capped at xxxLarge and expose
the system large-content viewer.

Verification: simulator build/install/launch passed; 30 AppTests passed. Overview, Position,
Groups and Profile visually inspected in both appearances; expense entry and split controls
opened in both appearances and the draft cancelled. Overview's balance, header and navigation
checked at accessibility-extra-large. This is not the full accessibility/VoiceOver matrix.
Calculated contrast: action labels 5.39:1 light / 8.20:1 dark; secondary text on page 5.12:1 /
8.70:1; avatar initials 4.55:1 / 6.03:1. Local screenshots: `/tmp/slice-cohesion-evidence/`.
The existing recent-activity scope defect remains #122; no ledger or sync behaviour changed.

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

### Cream appearance and payment profiles — #127

Carl's latest direction supersedes system-following appearance: warm cream-white, blue actions,
required name and Swedish/Danish phone at first use (also for incomplete existing profiles).
Edit a draft and validate before saving; retain the existing mutable profile wire/storage key.
Route payment handoff from the recipient's country, only for a matching debt currency.
Swish uses the previously device-verified shape. MobilePay opens the app with explicit phone
and amount copy controls; no unverified private-payment prefill. Never record on app launch.
Legacy/manual members can supply a number locally when paying; ownership is not SMS-verified.
Verify normalization/routing properties, persisted profiles, simulator onboarding/edit/payment
states and light appearance on a dark phone. Real app switching remains a physical-device gate.

Implemented: cream `#FAF7F0`, warm white surfaces, fixed light app appearance, draft-based
required name/phone setup and editing. Existing valid Swedish profiles remain valid. +46 routes
to Swish/SEK, +45 to MobilePay/DKK; other currency combinations explain the mismatch and retain
manual settlement. Overview lists the actual per-group recipient and exact transfer amount.
Manual payment confirmation is behind “Already paid?”; app switching never records payment.
Phone data stays in the existing mutable profile field, not the event log. No backend migration.

Verification: 140 Core tests passed, including 1,000 generated SE/DK round-trip and routing cases;
33 AppTests passed (profile validation, invalid-draft preservation, persistence/legacy migration,
Danish payee storage); 31 Sync tests passed after clearing a stale local SwiftPM build plan that
had omitted the newly added Core file. Final simulator build, install and launch passed.
Synthetic offline runtime checks: incomplete profile requires setup; invalid numbers disable save;
save and relaunch preserve profile; cancelled invalid edit retains the prior number; overview
opens the correct recipient/debt; Swedish/SEK shows Swish; Danish/DKK shows MobilePay; a
Danish-number/SEK mismatch offers no payment-app handoff. Copy controls yielded exactly
`+4520123456` and `100.00`. Missing payment apps show recovery text and leave both debts unchanged.
MobilePay payment view at accessibility-extra-large wraps copy controls and scrolls to cancel
and manual confirmation. App stays cream in the simulator's dark system appearance.
The currency menu now has its own accessibility label/value and 44pt target; it was previously
hidden behind the amount container's label during runtime inspection.

Limits: new phone ownership is not SMS-verified. Legacy/manual recipients may still need a number
entered locally; all users of this version must complete their own profile. Real Swish/MobilePay
app switching, return confirmation and two-phone number sharing remain #47/#48. Full VoiceOver,
iPad/narrow-phone coverage and deferred invite acceptance are not runtime-signed-off by this pass.
MobilePay's documented payment links are merchant flows, so no private prefill URL was invented:
https://developer.vippsmobilepay.com/docs/knowledge-base/payment-links/ . #122 remains open.

### Seamless logo palette — #129

The user rejected the cobalt/cream pass. Match the actual AppIcon's dominant `#4FA9E8`
(sampled from the asset), paired with Anthropic's documented light `#FAF9F5`:
https://github.com/anthropics/skills/blob/main/skills/brand-guidelines/SKILL.md .
Use one continuous ivory surface for page/card/navigation/launch, warm neutral placeholders,
dark labels on sky buttons, and a darker same-hue value only for readable links/icons. Remove
profile panel outlines and ornamental overview/navigation dividers. Keep field/error boundaries,
photos, payment behavior and all destinations. Validate contrast, build, existing AppTests and
inspect the main screens plus payment/expense sheets in the simulator before merge.

Implemented and checked: 33 AppTests pass. The first run caught a collapsed group-colour index;
the existing eight stable identity buckets are preserved, now using closely related warm neutrals.
Simulator inspection covered Overview, Groups, Position, Profile, payment/manual-confirmation,
expense entry and split selection. Payment and expense drafts were cancelled. Group/expense
shadows, profile panel borders and overview/navigation separators no longer split the canvas.
The static launch background also uses ivory. Calculated contrast: button text 5.61:1, inline
links 6.15:1, secondary text 5.51:1, primary text 14.64:1. This is visual simulator verification,
not new physical-device, full VoiceOver or launch-animation timing evidence.
Screenshot: `slice-seamless-overview.png` in the local 2026-09-29 visualization folder.
