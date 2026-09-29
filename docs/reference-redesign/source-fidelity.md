# Original-source fidelity pass — #133

The user supplied tubik's [AI-Powered Mobile App for Restaurant Operations](https://dribbble.com/shots/26787072-AI-Powered-Mobile-App-for-Restaurant-Operations) after the initial seven-screen adaptation (#131 / #132). The larger page images clarify details lost in the 420 × 315 attachment.

## Changes

- Lighter condensed headings, neutral charcoal surfaces and near-white controls; a stronger purple chart/category surface. These are visual approximations, not official design tokens or an identified original font.
- Compact 32pt circular glyph surfaces inside unchanged 44pt touch targets; leading back arrows on reports.
- Weekday labels above numeric circles showing actual expense counts, with selected-day state and accessible date/count labels.
- Two inset rounded metric panels inside the coral spending sheet.
- Overlapping rounded coral, charcoal and yellow category layers, with a small total pill. Category titles/icons stack at accessibility text sizes.
- Tighter overview spacing and one period selector beneath the timing dial.

Scope remains the seven compositions in the user's original image, mapped to Slice's features. Supplemental workers and map examples farther down the source page are not requirements for restaurant staffing or location tracking. Slice illustrations are original adaptations; see [artwork](artwork.md). The original source does not provide an inspectable component library, font files or UI token definitions, so no pixel-perfect claim is made.

## Verification

Built and installed on the iPhone 17 Pro / iOS 26.5 simulator, using synthetic data with sync disabled. Checked the numeric day selection, inset spending panels, category overlap, timing controls, back navigation and enlarged text. Corrected the missing English back label and category heading layout found during inspection. Existing data/ledger logic is unchanged; the previous 40 AppTests passed on the redesign baseline, not rerun for this visual-only follow-up.

Screenshots are saved in the local reference gallery's `source-fidelity/` folder. Physical-device, VoiceOver and two-device checks remain tracked separately under #123 / #47 / #48.
