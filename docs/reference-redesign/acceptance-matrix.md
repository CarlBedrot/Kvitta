# Slice — complete screenshot redesign

User direction, 2026-09-29: recreate ALL visible components of the attached reference for
Slice's existing expense/payment features. This supersedes the previous seamless ivory/blue
layout. The app icon/name and immutable ledger remain. Source attachment is 420 × 315;
small labels and fine illustration details are not legible. Full-resolution source requested.

## Visual language

Charcoal canvas and navigation; pale mint report surfaces; lavender chart/category panels;
coral statistic cards; butter-yellow illustrated cards; white pill selectors; condensed,
uppercase editorial titles; generous rounded panel corners; compact black badges; fine
chart axes/ticks. Do not substitute the last iteration's blank ivory list layout.

## Component contract

Every row must be implemented AND checked before calling the redesign complete.

| ID | Visible reference component | Slice destination / behavior | Status |
|---|---|---|---|
| 01 | Rounded charcoal screen shell | Main destinations and navigation | Implemented; verification in progress |
| 02 | Small avatar/identity strip | Profile and selected group | Implemented; verification in progress |
| 03 | Round utility buttons | Profile, back, dismiss, add | Implemented; verification in progress |
| 04 | White pill selectors | Group/currency/date/filter choices | Implemented; verification in progress |
| 05 | Condensed uppercase titles | All main page and card titles | Implemented; verification in progress |
| 06 | Stacked label/value hierarchy | Actual balances and expense totals | Implemented; verification in progress |
| 07 | Small status/percentage badges | Actual count/change/status, no invented metrics | Implemented; verification in progress |
| 08 | Compact charcoal insight card + yellow icon | Open settlement summary | Implemented; verification in progress |
| 09 | Lavender chart card | Actual daily expenses, selected currency | Implemented; verification in progress |
| 10 | Seven circular day controls | Selected day / recent-day expense filter | Implemented; verification in progress |
| 11 | Coral area chart, baseline and legend | Expense timeline | Implemented; verification in progress |
| 12 | Black bottom icon bar + pastel selected icon | Existing four destinations and add action | Implemented; verification in progress |
| 13 | Mint report cover panel | Reports hub | Implemented; verification in progress |
| 14 | Large illustrated report hero | Slice illustration, not generic icon substitution | Implemented; verification in progress |
| 15 | Search pill with magnifier/filter affordance | Search real expenses | Implemented; verification in progress |
| 16 | Pinned report row with circular category icon | Selected report / most-used category | Implemented; verification in progress |
| 17 | Yellow circular plus | Add expense action in report hub | Implemented; verification in progress |
| 18 | Dark editorial activity/conversation layout | Actual ledger activity, clearly labelled as records | Implemented; verification in progress |
| 19 | Avatar-led information block | Expense author/group information | Implemented; verification in progress |
| 20 | Rounded right-aligned information/suggestion pills | Filter chips and selected search criteria | Implemented; verification in progress |
| 21 | Rounded input with coral leading action | Expense search, never a pretend AI assistant | Implemented; verification in progress |
| 22 | Coral metric sheet with stacked summary rows | Selected-currency expense report | Implemented; verification in progress |
| 23 | Week/date selector and previous/next controls | Actual report period | Implemented; verification in progress |
| 24 | Seven rounded mint bars with highlighted value | Daily totals in chosen period | Implemented; verification in progress |
| 25 | Dark payment/service page with white filter pills | Payment profile and sync settings | Implemented; verification in progress |
| 26 | Tilted overlapping coral/yellow/mint cards | Swish, MobilePay and sync/profile actions | Implemented; verification in progress |
| 27 | Service logos/marks and circular navigation arrows | Clearly labelled payment provider controls | Implemented; verification in progress |
| 28 | Lavender category screen | Expense category explorer | Implemented; verification in progress |
| 29 | Nested coral, charcoal and yellow category tabs | Actual category selection | Implemented; verification in progress |
| 30 | Large illustrated category card + small metadata | Category totals and matching expense list | Implemented; verification in progress |
| 31 | Mint timing page | Expense activity by day of week | Implemented; verification in progress |
| 32 | White circular dial, ticks, numerals and coral arc | Weekly expense count distribution, real data | Implemented; verification in progress |
| 33 | Period controls beneath dial | Report period selection | Implemented; verification in progress |

## Data and behavior boundaries

- Display actual expenses and payments; include the user's own activity in reports.
- Never add different currencies, reinterpret currency, or use Float/Double to calculate money.
- Charts are read-only projections; immutable events, stored shares and sync are unchanged.
- All visible controls must work. No decorative fake AI conversation, business integration,
  random revenue metrics, artificial ratings or claim of payment-provider connection.
- Category/provider/group cards open their actual destinations. Keep name/phone setup,
  Swish/MobilePay currency safeguards and explicit payment confirmation.
- Empty states must still expose the visual components with accurate zero/no-data states.
- English/Swedish, Dynamic Type, accessible chart summaries, 44pt targets, Reduce Motion.

## Verification

Build, existing tests plus meaningful report projection tests; real simulator inspection of
all seven reference compositions; compare each matrix row with screenshots. Keep "implemented",
"runtime checked" and physical-device results separate. Parent private-beta work #119 continues. Implementation issue: #131.
See [verification](verification.md) and [artwork provenance](artwork.md).
