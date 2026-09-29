# Slice — complete screenshot redesign

User direction, 2026-09-29: recreate ALL visible components of the attached reference for
Slice's existing expense/payment features. This supersedes the previous seamless ivory/blue
layout. The app icon/name and immutable ledger remain. The initial attachment was 420 × 315.
The user subsequently supplied the original [tubik design on Dribbble](https://dribbble.com/shots/26787072-AI-Powered-Mobile-App-for-Restaurant-Operations).
See [source fidelity follow-up](source-fidelity.md) for the refinements informed by the larger source.

## Visual language

Charcoal canvas and navigation; pale mint report surfaces; lavender chart/category panels;
coral statistic cards; butter-yellow illustrated cards; white pill selectors; condensed,
uppercase editorial titles; generous rounded panel corners; compact black badges; fine
chart axes/ticks. Do not substitute the last iteration's blank ivory list layout.

## Component contract

Every row must be implemented AND checked before calling the redesign complete.

| ID | Visible reference component | Slice destination / behavior | Status |
|---|---|---|---|
| 01 | Rounded charcoal screen shell | Main destinations and navigation | Implemented; simulator checked |
| 02 | Small avatar/identity strip | Profile and selected group | Implemented; simulator checked |
| 03 | Round utility buttons | Profile, back, dismiss, add | Implemented; simulator checked |
| 04 | White pill selectors | Group/currency/date/filter choices | Implemented; simulator checked |
| 05 | Condensed uppercase titles | All main page and card titles | Implemented; simulator checked |
| 06 | Stacked label/value hierarchy | Actual balances and expense totals | Implemented; simulator checked |
| 07 | Small status/percentage badges | Actual count/change/status, no invented metrics | Implemented; simulator checked |
| 08 | Compact charcoal insight card + yellow icon | Open settlement summary | Implemented; simulator checked |
| 09 | Lavender chart card | Actual daily expenses, selected currency | Implemented; simulator checked |
| 10 | Seven circular day controls | Selected day / recent-day expense filter | Implemented; simulator checked |
| 11 | Coral area chart, baseline and legend | Expense timeline | Implemented; simulator checked |
| 12 | Black bottom icon bar + pastel selected icon | Existing four destinations and add action | Implemented; simulator checked |
| 13 | Mint report cover panel | Reports hub | Implemented; simulator checked |
| 14 | Large illustrated report hero | Slice illustration, not generic icon substitution | Implemented; simulator checked |
| 15 | Search pill with magnifier/filter affordance | Search real expenses | Implemented; simulator checked |
| 16 | Pinned report row with circular category icon | Selected report / most-used category | Implemented; simulator checked |
| 17 | Yellow circular plus | Add expense action in report hub | Implemented; simulator checked |
| 18 | Dark editorial activity/conversation layout | Actual ledger activity, clearly labelled as records | Implemented; simulator checked |
| 19 | Avatar-led information block | Expense author/group information | Implemented; simulator checked |
| 20 | Rounded right-aligned information/suggestion pills | Filter chips and selected search criteria | Implemented; simulator checked |
| 21 | Rounded input with coral leading action | Expense search, never a pretend AI assistant | Implemented; simulator checked |
| 22 | Coral metric sheet with stacked summary rows | Selected-currency expense report | Implemented; simulator checked |
| 23 | Week/date selector and previous/next controls | Actual report period | Implemented; simulator checked |
| 24 | Seven rounded mint bars with highlighted value | Daily totals in chosen period | Implemented; simulator checked |
| 25 | Dark payment/service page with white filter pills | Payment profile and sync settings | Implemented; simulator checked |
| 26 | Tilted overlapping coral/yellow/mint cards | Swish, MobilePay and sync/profile actions | Implemented; simulator checked |
| 27 | Service logos/marks and circular navigation arrows | Clearly labelled payment provider controls | Implemented; simulator checked |
| 28 | Lavender category screen | Expense category explorer | Implemented; simulator checked |
| 29 | Nested coral, charcoal and yellow category tabs | Actual category selection | Implemented; simulator checked |
| 30 | Large illustrated category card + small metadata | Category totals and matching expense list | Implemented; simulator checked |
| 31 | Mint timing page | Expense activity by day of week | Implemented; simulator checked |
| 32 | White circular dial, ticks, numerals and coral arc | Weekly expense count distribution, real data | Implemented; simulator checked |
| 33 | Period controls beneath dial | Report period selection | Implemented; simulator checked |

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

## Completion note

All 33 mapped component types are present and visually checked across the seven compositions.
Control routes were exercised for reporting, categories, periods, currency/group selection,
activity filters/search, expense details/add/edit, profile/account cards and direct debt actions.
Illustrations and labels are adapted for Slice; component coverage is not a claim of
pixel-perfect reproduction. The original source supports a closer visual comparison, but
does not supply font files or exact UI tokens. Broad hardware/VoiceOver and two-device QA remain #123/#47/#48.
