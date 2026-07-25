# UI Design: Expense App (final direction, July 2026)

Feeds Session 2 and all SwiftUI work. Read together with docs/expense-app-sync-design.md.
Visual reference: docs/mockup.html (authoritative for palette, layout, and tone).

## Design stance

Native iOS 26+ money app for a Nordic friend group, in the Liquid Glass design language (mandatory for all apps by iOS 27; we build glass-native from day one).

Liquid Glass rules as applied here:
- Glass lives ONLY on the control layer: floating tab bar, FAB, buttons, chips, sheet chrome. Content (cards, balances, expense lists, the zero line) is always opaque and calm. Content is primary; chrome recedes.
- Use system components on the iOS 26 SDK and inherit correct glass on navigation, tab bar, sheets, menus, and toolbars for free. Use the glass effect APIs manually only for the FAB and settle/save buttons.
- Restraint rule: if more than three glass elements are visible on one screen, something is wrong.
- Floating capsule tab bar (system default on iOS 26); content scrolls underneath it.

The two signature elements:
1. **Amount-first entry.** The add sheet opens straight into a large amount over a keypad, Swish-style. The 90% case is two fields: amount + description, then Spara. Under 10 seconds standing at a register.
2. **The zero line.** Balances render on a horizontal axis centered at zero: bar extends left (you owe, clay) or right (you are owed, sage). Settling up collapses the bar to center with a soft haptic. This is the app's one visualization.

## Tokens

Palette (warm cream, Anthropic-adjacent):
- Background: cream #F3EFE6 with soft ambient washes (clay hint #F8E9DC, sage hint #EDF0E3) so glass has something to refract
- Cards: warm white #FFFDF7, radius 26, whisper shadow
- Ink: espresso #2A2620; secondary #8A8377; hairlines rgba(70,60,40,.12)
- Positive (you are owed): sage #4F7D58
- Negative (you owe): clay #C25E3C (warm, not alarm-red; owing a friend is not an error)
- Accent: soft clay #D97757 for the FAB (the one pop of color per screen)
- Primary buttons (Spara, dark actions): espresso glass, cream text
- Swish button keeps Swish pink (user recognition beats palette purity)
- Dark mode: derive warm dark (espresso backgrounds, cream text, same sage/clay), tune by eye in Session 2

Known tension, accepted: clay is both accent and owe-color. Acceptable because amounts always carry sign and direction words. If it ever confuses in practice, darken negative amounts to rust and keep clay for accent only.

Type:
- UI text: SF Pro, Dynamic Type styles only
- All amounts: SF Rounded (ui-rounded), monospaced digits, semibold. Amounts are the loudest thing on any screen.
- Direction always in words next to the number ("du ska fa 512 kr"); color never carries meaning alone.

Motion:
- One orchestrated moment: settle-up collapsing the zero line to center + soft haptic + small celebration on reaching 0 kr ("ni ar kvitt"). Everything else default SwiftUI. Respect Reduce Motion.

## Information architecture

Three tabs in a floating glass capsule: **Grupper** (home), **Aktivitet** (event feed), **Jag** (profile, settings, synkstatus, CSV-export). Tab is "Jag", never "Du", and uses a person glyph (SF Symbol person.crop.circle), no smiley.

Add expense: clay glass FAB on Grupper and group screens, opens the add sheet with most recent group preselected.

Localization: Swedish and English from day one (String Catalog), Swedish is the reference copy.

## Categories and emoji

Every expense has a category with a default emoji, shown as the row's leading element (warm cream circle):
groceries 🛒, alkohol 🍷, restaurang 🍽️, brunch 🥞, taxi 🚕, resa 🏖️, boende 🏠, sport 🎾, nöje 🎉, övrigt 🧾.
Groups can have an emoji in the name. Description suggestion chips (from the user's history) show their category emoji. Emoji is data (categoryId -> default emoji, overridable per expense later), not decoration hardcoded in views.

## Screens (layouts per mockup.html)

1. **Hem (Grupper)**: Totalt card (net amount + zero line), group rows with name, net, mini zero line, sorted by last activity. Clay FAB. Empty state invites creating a group.
2. **Ny utgift (sheet)**: group menu top-left, big amount over custom keypad, description field with emoji suggestion chips, one summary row "Du betalade · delas lika (4)" opening the split editor (Lika/Exakt/Procent/Andelar, live remainder validation, Spara disabled until the invariant holds). Espresso Spara button. Save = haptic, instant local appearance, never a spinner.
3. **Gruppvy**: balance card + zero line, "Vem ar skyldig vem" simplified transfers with glass Gör upp buttons, expense list by month with emoji circles and "din del X kr". Toolbar: add member, settings, CSV export. Unsynced rows get a small dashed-cloud badge.
4. **Balansgranskning** (trust view): tap any balance/transfer -> every contributing expense and payment with running total ending at exactly the tapped number. First-class screen.
5. **Gör upp**: amount, zero-line preview, "Efter betalningen: 0 kr · ni ar kvitt", Swish button (SEK, prefill deep link) or MobilePay flow (DKK), Markera som betald. On return: confirm -> PaymentRecorded -> collapse animation.
6. **Utgiftsdetalj**: shares, payer, edit history from events, edit/soft delete, restore via "Visa borttagna".
7. **Aktivitet**: chronological cross-group feed from the event log.

## Offline and sync in the UI

- Never a loading state on launch or navigation; projections are local.
- Unsynced items: dashed-cloud badge on the row, nothing modal.
- Sync problems live under Jag -> Synkstatus; a single dismissible banner only for auth failures or rejected events, with a retry detail screen.
- Adding expenses is never blocked by any network condition.

## Accessibility floor

- Dynamic Type through XXL; amounts wrap, never shrink below body size
- VoiceOver reads direction + amount + counterpart ("Du ar skyldig Jonas 152 kronor")
- 44pt touch targets; standard haptics; Reduce Motion disables the settle animation, keeps the haptic
- Glass legibility: rely on system materials and vibrancy, never hand-tuned opacity on text over glass

## Explicitly not in v1

- Custom theming, onboarding carousels, statistics/chart screens (the zero line is the visualization)
- Widgets and App Intents (fast follow; architecture supports them)
- Comments UI (v1.1 with CommentAdded events)
