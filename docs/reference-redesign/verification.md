# Reference redesign verification — 2026-09-29

## Automated

- AppTests: **40 passed, 0 failed** on iPhone 17 Pro / iOS 26.5.
- Result: `/tmp/slice-reference-tests-final.xcresult`.
- New coverage: own/partner expense activity, edit/delete and own pending repayment;
  unchanged news scope; deterministic order and empty activity; primary currency in an empty
  DKK group; exact currency/category/search/date filtering; Monday–Sunday/year/leap boundaries;
  conservation across daily/category totals; Int64 overflow and values above Double's exact range.
- No backend, ledger event, amount rounding, stored share, currency conversion or sync changes.
- Reports aggregate shared group spending; payments are activity records, never revenue.

## Simulator

Device: `Slice-Merge-Review`, UUID `C09FC266-C775-4965-B3C8-35972E17B29C`.
Synthetic offline test data only; no payment was executed.

- Dashboard, mint reports cover, coral spending report, stacked category card, expense activity,
  mint weekly dial and tilted payment cards visually inspected.
- Report retained SEK after opening the SEK chart (a currency reset was caught and fixed).
- Selected-day chart badge showed the exact total; previous week showed zero expenses and
  an empty dial; returning to current week was enabled.
- Phone label overlap caught in payment cards and spacing adjusted.

Remaining checks are recorded below as they finish. Simulator evidence does not claim actual
Swish/MobilePay handoff, a second phone, VoiceOver on hardware, or public production readiness.
Those gates remain #47, #48, #123 and #68.

## Completed interaction checks

- Swedish and English rendered with real content. Missing Categories translation and two legacy
  history phrases were caught and corrected.
- Provider filter hides/shows the account card; Swish opens the existing profile editor; cancel
  leaves the number unchanged; account card opens real sign-in status.
- Direct debt action opened Jonas / 100 DKK / +45 / MobilePay with explicit copy controls.
  Cancelled without recording payment.
- Report yellow plus dismissed reports and opened the real expense form. Saved `Reference QA`
  for 120 SEK, opened it from Overview, edited its title, and confirmed `Reference QA edited`
  plus the edit marker on Overview. Split remained 40 SEK per member.
- Activity search returned the edited record; clear restored all records; Payments filter showed
  the repayment; tapping it navigated to its actual group. Notification scope remains separate.
- Large accessibility text checked on dashboard, report metrics and payment cards. Fixed icon
  sizing, vertically stacked group/currency selectors and service-card contents avoid truncation.
- Existing group list, group expense route and balances inspected. Removed the leftover group
  mesh background and matched the group navigation to the shared charcoal/mint/yellow roles.

Screenshots are in the task artifact folder `reference-redesign/`: dashboard, payments,
large-text, reports and own-edited-expense, plus the remaining report compositions.

## Final pass

- Group selector retained Fjällresan and SEK in reports. Category selection changed Restaurant
  / 1000 SEK to Alcohol / 437 SEK and the matching Systembolaget entry.
- Final dial has upright weekday labels and exact count accessibility summaries.
- Activity's coral search composer remains visible at the bottom while records scroll.
- Expense details close back to the current report without resetting its state; created/edited
  attribution is translated in English. Explicit close also works without a swipe gesture.
- Final build/install/launch checked after layout-only adjustments; the 40-test suite preceded
  those final layout/copy adjustments. Both backend CI variants, Core CI and secret scan passed
  on the implementation commit; final PR checks must pass before merge.

## Groups match Categories — #135 (2026-09-30)

Groups now share `EditorialCardStack`, `EditorialCardTitle` and `EditorialMetadataPill`
with Categories: identical purple/coral/charcoal/yellow roles, overlapping rounded layers,
condensed title, metadata pills and illustration treatment. A saved group photo replaces
the default illustration. Group names, member/expense counts and each currency's balance
remain actual group data. Search, profile and group creation stay available.

Validation: iPhone 17 Pro / iOS 26.5 build, install and launch passed. Simulator checks
covered opening Fjällresan and returning, separate 4.65 SEK owed-to-you / 100 DKK owed
balances, unmatched search and clear, new-group sheet opening/cancel, and normal versus
accessibility-extra-large text. Categories retained its appearance and selection changed
Restaurant (1000 SEK) to Alcohol (437 SEK). Screenshots are in the local `groups-category`
artifact folder. Empty-account and custom-photo variants were source-reviewed, not separately
runtime exercised. Ledger logic was unchanged; no new layout-only tests were added.

## Group Spending and Payments — #137 (2026-09-30)

The Spending composition now appears inside each group. Categories-style group cards remain
in the group picker. Expenses uses group-scoped weekly totals/largest expense and mint daily
bars. Payments uses settled repayment totals and the current personal balance; labels distinguish
period totals from the current balance. Currency and week selectors are shared across the two
tabs for that visit. Full expense and repayment histories are explicitly labelled separately.
The repayment chart follows `Payment.countsTowardBalances`: confirmed and aged pending payments
count, disputed and still-unconfirmed payments do not. Int64 totals detect overflow. Existing
settlement/confirmation paths remain; the current balance opens its audit. Photo, member and
conversion controls remain under Group information and the toolbar menu.

43 AppTests passed, including new tests for repayment currency/period/group isolation, status
policy, daily conservation, exact large integers and overflow. Simulator checks covered 1657 SEK
weekly spending, 100 SEK and 200 DKK settled repayments in separate buckets, 4.65 SEK owed-to-you
and 100 DKK owed balances, the previous-week empty state, the balance audit and opening/cancelling
the 100 DKK MobilePay sheet. No payment was recorded. An accessibility-extra-large check found
bottom navigation wrapping; the controls now stack at accessibility sizes. A subsequent build
and simulator check cover that layout-only correction. Artifacts: local `group-spending` folder.

## Compact group picker — #140 (2026-09-30)

Each overlapping colored layer now represents a real group and opens that group. The most
recently active group is the illustrated front card; older group names remain visible above
it. A single group produces one card. The picker contains group identity only: member counts,
expense counts and financial summaries belong inside the group. The purple canvas and pizza
artwork remain, with the front illustration reduced to 190pt and the stack capped at 520pt wide.

Member/expense counts now lead group detail. Group Spending uses a smaller heading and 160pt
bar chart. The compact menu stays horizontal with 44pt targets and the same navigation text-size
cap as the root menu; the rest of the content still honors accessibility text sizes.

Validation: simulator build/install/launch passed. Two real local groups were checked: Norrebr
opens with 1 person / 0 expenses; Fjällresan with 3 people / 6 expenses and unchanged 1657 SEK
weekly spending. Search was checked with one match, no matches and clear. Both layers navigate
to their own group. Normal-size screenshots show the complete picker and compact group detail.
No ledger or projection changes; the earlier 43 AppTests were not rerun for this layout change.
Local screenshots: `compact-groups`. Simulator text preferences are restored to normal and the
app relaunched after accessibility inspection, avoiding the stale enlarged preview.

## Accessibility review — PR #139 (2026-09-30)

Reviewed the PR against current main, including the compact group picker. Profile edit,
sign-out and diagnostic controls have 44pt minimum heights; reminder and payment controls
have explicit accessibility labels; activity rows expose a combined description. Settlement
and deleted-expense animations respect Reduce Motion.

Review corrections: names wrap instead of being forced into one truncated line. The new-expense
form scrolls when content or the keyboard needs more room, and its summary wraps. At accessibility
text sizes, split modes use two columns, and payer/member widths scale with the text. Normal text
retains the compact split layout and the existing root/group menu design.

Validation: 43 AppTests passed on the integrated PR before the additional layout-only corrections;
the final corrected app builds, installs and launches in the iOS 26.5 simulator. Normal-size checks
covered Profile labels, Overview payment/activity labels and expense/split entry. At accessibility-
extra-large, Groups, expense entry and the split editor were inspected visually. A local-only QA
expense saved 120 SEK with three 40 SEK shares, edited to 150 SEK with three 50 SEK shares, then
was recoverably deleted. No external payment was made. Screenshot: local `a11y-review/split-large.png`.

Still unverified: real VoiceOver traversal, Reduce Motion interaction on a device, long-name end-to-end
entry, full keyboard/narrow-phone/iPad coverage, every split mode, restore and recorded-settlement flows
on this revision, and physical two-phone sync/payment handoff. Native simulator automation could not
activate some navigation-bar controls; an attempted long-name group was cancelled without saving.
Issue #123 stays open; this PR resolves specific findings, not the entire acceptance matrix.
