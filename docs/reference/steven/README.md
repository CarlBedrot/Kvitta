# Steven-referensen — källan för Slice-UI:t

**Från 2026-10-20 är den här mappen facit för hur Slice ser ut och beter sig.** Den ersätter
`docs/reference-redesign/` (tubik-referensen, #131/#133) och de tidigare design-issues #119/#123.
Målet: Slice ska se ut och bete sig nästan exakt som Steven. De enda avvikelserna är våra bilder
(gruppbanners, avatarer, appikon) och vår blå brand-färg i stället för Stevens teal, plus att
Steven-funktioner vi saknar plockas bort (se [Avvikelser](#4-avvikelser-från-steven)).

Arkitekturen rörs inte. Allt renderas från den lokala ledgern, sync går bara i bakgrunden, och
inga eventtyper eller payloads ändras. Det här är en UI-omgörning.

Märkning i texten:
- **[bild]**: läst direkt ur en skärmdump.
- **[gissning]**: syns inte i någon bild och är härlett av mig. Ska verifieras eller beslutas.
- **[beslut]**: Carl har besvarat frågan (se avsnitt 6).

Alla bilder är iPhone-skärmdumpar på 1170×2532 px (@3x, 390×844 pt). Mått nedan är i punkter.

---

## 1. Skärminventering

| # | Fil | Skärm | Tillstånd i bild |
|---|-----|-------|------------------|
| 01 | `01-grupper-lista.png` | Grupper (flik 1), toppen | laddad, blandade saldon |
| 02 | `02-grupper-lista-scrollad-arkiverade.png` | Grupper, botten | kvitta grupper + "VISA ARKIVERADE" |
| 03 | `03-konto.png` | Konto (flik 2) — Stevens plånbok | **ska inte med** |
| 04 | `04-notiser.png` | Notiser (flik 3) | olästa notiser, badge 495 |
| 05 | `05-mer.png` | Mer (flik 4), toppen | profilhuvud + lista |
| 06 | `06-mer-scrollad.png` | Mer, scrollad | resten av listan |
| 07 | `07-mina-detaljer.png` | Mer → Mina detaljer | ifylld profil |
| 08 | `08-grupp-utgifter.png` | Grupp → flik UTGIFTER | laddad, månadssektion |
| 09 | `09-grupp-stallning.png` | Grupp → flik STÄLLNING | två medlemmar, ihopfällda |
| 10 | `10-grupp-betalningar-tom.png` | Grupp → flik BETALNINGAR | tom (bara info-kort) |
| 11 | `11-grupp-installningar.png` | Grupp → `•••` → Inställningar | |
| 12 | `12-ny-utgift-belopp-tom.png` | Ny utgift steg 1 (belopp) | tomt belopp, Nästa avstängd |
| 13 | `13-ny-utgift-belopp-ifyllt.png` | Ny utgift steg 1 | 100 SEK, Nästa aktiv |
| 14 | `14-ny-utgift-detaljer-fordelning.png` | Ny utgift steg 2 (detaljer) | beskrivning, kategori, 50/50 |
| 15 | `15-utgift-detalj.png` | Utgiftsdetalj (ark) | betald av mig, en deltagare |

Mörkt läge finns inte i någon bild (härleds, 6.3). Fel- och laddningstillstånd syns inte heller; vi behåller dagens beteende (`SyncStatusBanner`, felalerts) i Steven-form.

### 1.1 Navigation

```
TabView — Steven: Grupper · Konto · Notiser · Mer. Slice (6.1): Grupper · Notiser · Mer
├── Grupper ── (tryck kort) ──▶ Grupp [push]
│     │                          ├── flikar UTGIFTER | STÄLLNING | BETALNINGAR
│     │                          ├── (tryck utgiftskort) ─▶ Utgiftsdetalj [sheet] ─ Ändra ─▶ Utgift steg 2 (redigera)
│     │                          ├── (+ FAB) ─▶ Ny utgift [sheet]: steg 1 belopp ─ Nästa ─▶ steg 2 detaljer ─ Spara
│     │                          ├── (Påminn / Betala i footern) ─▶ [gissning] påminn/gör upp
│     │                          └── (•••) ─▶ Inställningar [push]
│     ├── (Ny grupp +) ─▶ Ny grupp [gissning: sheet]
│     ├── (swipe vänster på kvitt grupp) ─▶ arkivera
│     └── (VISA ARKIVERADE) ─▶ arkiverade grupper [gissning: push, samma kortlista]
├── Notiser ── (tryck notis) ─▶ [gissning] utgiftsdetalj i rätt grupp; markeras läst
└── Mer ── Mina detaljer [push] · övriga rader [push]
```

Tab bar **[bild]**: vit bakgrund, en hårfin linje överst, fyra lika breda flikar med ikon och etikett.
Aktiv flik har fylld ikon och accentfärg, inaktiva har konturikon och grå färg (#A2A2A2). Röd
badge (#FF383C) med vit siffra sitter uppe till höger om ikonen.

### 1.2 Skärm för skärm

**Grupper (01, 02)**
- Rubrik "Grupper" vänsterställd (28 pt semibold, #4A4D5C). Till höger "Ny grupp" + tunt `+`, båda i accentfärg.
- (Steven: "Prenumerationer", en konturknapp i full bredd. **Tas bort.**)
- Ett kort per grupp: vitt, radie 8, svag skugga, 16 pt sidmarginal och 12 pt mellan korten. Innehåll med 16 pt padding:
  - Gruppnamn, 22 pt bold, #3A3C4A, emoji tillåtna ("Dublin🇮🇪☘️").
  - Avatarstapel: 38 pt cirklar som överlappar ca 4 pt. Du själv först, sedan övriga i namnordning. Foto om det finns, annars initialer (17 pt, #3A3C4A) på en pastellplatta (se 2.1).
  - Fotrad: vänster "N vänner" (17 pt, #9FA1AC; N = medlemmar utom du, "1 vän" i singular). Höger ett av tre lägen:
    - de är skyldiga dig: "De är skyldiga" (grå) + **belopp** (bold, ljus accent — Steven #24E6D3)
    - du är skyldig: "Du är skyldig" (grå) + **belopp** (bold, korall #FECCB5)
    - kvitt: "Dra vänster för att arkivera" (grå) + **Kvitt** (bold, accent)
- Swipe vänster på ett kort arkiverar gruppen **[bild: hinttexten]**. Om det bara går för kvitta grupper är **[gissning]**; hinten visas bara på dem.
- Längst ner "VISA ARKIVERADE" (15 pt semibold versaler, #7D7E85) som öppnar listan över arkiverade grupper.
- Tomt läge **[gissning]**: rubrik + "Ny grupp" + en centrerad text "Inga grupper än" och knappen "Skapa grupp", eller gå med via länk.

**Grupp (08, 09, 10)**
- Navigationsrad: `‹` vänster, `•••` höger (öppnar Inställningar). Ingen titel i raden.
- Huvud: gruppnamn vänster (26 pt bold) och gruppens totala utgifter höger (26 pt bold, "53 545,08 kr"). Under: medlemmarnas avatarer, 44 pt med 16 pt mellanrum (ingen överlapp). En liten stjärnbricka (korall ring, 16 pt) nere till höger på en avatar. **[gissning: gruppens skapare/admin]**
- Flikrad: UTGIFTER · STÄLLNING · BETALNINGAR. 15 pt bold versaler, lika breda. Vald flik i #3A3C4A med 3 pt accentlinje under, övriga #AAAAAA. Hårlinje #DBDBDD under hela raden.
- Innehållsyta #F9F9FA.
- **UTGIFTER**: månadssektioner "OKT. 2026" (15 pt versaler, #7D7E85, hårlinje under). Nyast först. Ett kort per utgift:
  - Ikoncirkel 44 pt med kvittoikon. Tonad accent (#D1F0ED) när **du** betalade, tonad korall (#FFF5F0) när någon annan betalade **[bild: härlett av tre kort]**.
  - Titel 17 pt bold, datum "måndag, 19 okt." 15 pt, belopp höger 17 pt bold.
  - Fotrad 15 pt bold #C8C9CE: vänster "Du och 1 vän" om du deltar, annars "N vänner" (Steven skriver felaktigt "1 vänner"; vi böjer rätt). Höger "Carl betalade".
- **STÄLLNING**: ett vitt kort per medlem med avatar 40, namn "Ellen E" (förnamn + initial i efternamn, 17 pt bold), saldo höger (minus = korall, plus = accent), vertikal skiljelinje och `⌄`. Tryck fäller ut **[gissning: vem som är skyldig vem, i par, med Betala/Påminn per par]**. Sorterat med minst saldo först **[bild]**.
- **BETALNINGAR**: info-kort "Så här beräknar vi betalningar / Läs mer här" (ikon `i` på ljus cirkel). Under kortet listas betalningar **[gissning: registrerade betalningar i gruppen, nyast först, med status Väntar/Bekräftad/Bestridd]**.
- Fast footer, vit, med skugga uppåt:
  - vänster "De är skyldiga" (17 pt grå) + belopp (22 pt bold accent)
  - höger konturknapp "Påminn" (accent, radie 6, 1.5 pt kant, 110×44)
  - mitt FAB 60 pt fylld cirkel (Steven #1ADDC4) med mörkt `+`, som sticker upp över footern. FAB öppnar Ny utgift.
  - **[beslut 6.4]** när du är skyldig: "Du är skyldig" + korallbelopp + fylld knapp "Betala". När allt är kvitt: "Kvitt" och ingen knapp. Påminn öppnar delningsarket.

**Gruppinställningar (11)** — nav-titel "INSTÄLLNINGAR" (17 pt bold versaler, centrerad), vanlig lista med hårlinjer och sektionsrubriker i versaler:
- GRUPPNAMN: namnet, redigerbart direkt i raden **[gissning]**.
- Statistik `›` (Steven har en uppgraderingspil här; vi har ingen betalnivå, så den visas inte).
- DELTAGARE: avatarstapel + antal + `›` (medlemslista). "Lägg till medlemmar" `›`. "Grupplänk" `›` (dela inbjudningslänk).
- GENERAL: "Återkommande utgifter" — **tas bort** (vi har inte återkommande).
- Fristående: "Arkivera grupp", "Lämna grupp" (ikon + text, ingen chevron).

**Ny utgift steg 1 — belopp (12, 13)** — ark som täcker skärmen; bakom syns svart och en grå "kortkant":
- Huvud: `✕` vänster, titel "UTGIFT ⌄" centrerad. ⌄ öppnar typbyte **[gissning: Utgift / Betalning]**.
- (Steven: raden "Dela transaktioner från din bank ›". **Tas bort.**)
- Betalarchip "(avatar) Carl betalade ›": kontur, radie 6. Öppnar val av betalare **[gissning: lista över medlemmar; flera betalare om vår modell tillåter]**.
- Beloppet centrerat (64 pt heavy). Tomt visas en grå "0" (#C5C5C7), ifyllt #3A3C4A. Valutachip "SEK ›" (kontur) bredvid öppnar valutaväljaren.
- Verktygsrad: räknare (+−×÷), galleri, kamera; till höger "Nästa" (accent, radie 6, vit bold text). Avstängd i ljus ton (#8DDBD3) tills beloppet är > 0.
- Egen sifferknappsats 3×4 (1–9, `,`, 0, ⌫). Hårlinjer i rutnätet, 28 pt siffror, grå (#D6D9DE) area under som tangentbord.

**Ny utgift steg 2 — detaljer (14)** — `‹` tillbaka, titel "UTGIFT":
- Beskrivningsfält överst (stor, ingen ram; platshållare = vald kategori **[gissning]**).
- Kategorichips i en horisontell rad: grå (#EBEBEC, radie 6), den valda vit med skugga och bold text, `…` sist för fler.
- DELTAGARE: per medlem avatar 40, namn, andel i kr (15 pt grå), procentfält (kontur, radie 6, "50 %"), kryssruta (accentfylld rundad fyrkant med vit bock). Bockas någon ur fördelas andelarna om lika.
- "Återställ till att dela lika" (accent, bold länk).
- ANNAN: "Datum — Idag ›" (öppnar datumväljare), "Upprepa" (**tas bort**).
- Knappen "Spara" i full bredd längst ner (accent, radie 6, 50 pt hög; Steven skriver "Save").

**Utgiftsdetalj (15)** — ark, `✕` vänster, titel = utgiftens namn i versaler, "Ändra" (accent) höger:
- Betalarens avatar 70 pt centrerad, sedan "Carl betalade **368 kr**" och "för Køben" (20 pt, centrerat).
- Datum "måndag 19, okt. 2026" (17 pt grå).
- "Deltagare" (15 pt grå) och rader med avatar 40, förnamn och belopp höger (grå).
- Fotnot "Utgift skapad manuellt, av Carl Bedrot, 19 okt., 2026, 16:40" (15 pt grå).
- **[gissning]** Ta bort ligger i redigeringsläget (Ändra → längst ner "Ta bort utgift").

**Notiser (04)**
- Rubrik "Notiser" (28 pt) och "Läs alla" (accent) till höger.
- Kort per händelse: korall-tonad bakgrund (#FEEFE8) när oläst **[gissning: vit när läst]**, avatar 44, text "**Ellen Ekwall** lade till dig i utgiften "**Middag puss**"." (Steven blandar engelska; vi skriver svenska) och relativ tid "1 vecka sedan" (15 pt, #C4C4C9).
- Badge på fliken visar antalet olästa.

**Mer (05, 06)**
- Profilhuvud: avatar 70 pt, namn (22 pt bold) och undertext (Steven: kontonivå "Steven Free"; vi visar **[gissning]** telefonnumret).
- (Steven: kortet "Chatta med oss". **Tas bort**, se 4.)
- Lista i full bredd, rad 60 pt, ikon 24 pt (kontur) + text 17 pt + `›` eller toggle:
  Steven-raderna vi behåller är Mina detaljer (avatar som ikon), Hjälpcenter, Om appen och Dela till en vän. Uppgradera, Göm erbjudanden, Bankanslutningar, Säkerhetskod, Face ID och Betygsätt tas bort.
- Våra extra rader i samma radstil (se 4): Utseende, Betaltjänster, Påminnelser, Exportera, Utvecklarverktyg (DEBUG/trial).

**Mina detaljer (07)** — nav-titel "MINA DETALJER", ett vitt kort med rader "etikett vänster (grå) — värde höger (#4B4D5B)" och hårlinjer emellan:
- Profilbild (avatar 40), Namn och Telefon (vårt Swish/MobilePay-nummer). Adress och E-post **tas bort** (vi har dem inte).
- Steven visar "Förnamn" i accentfärg, vilket antyder att raden går att redigera. Vi gör alla rader redigerbara genom tryck (push till ett redigeringsfält) **[gissning]**.
- "LOGGA UT": konturknapp i full bredd, versaler, accent. Visas bara när servern är inloggad.
- Grå text med understruken länk "ta bort mitt Slicekonto" **[gissning: bara när inloggad]**.

**Konto (03)** — Stevens plånbok, kort och bankutbetalningar. **Ingen motsvarighet; tas bort.**

---

## 2. Designsystem (SwiftUI-tokens)

Härlett med pixelsampling av skärmdumparna. Teal ersätts med vår blå (se 4). Ljust läge är
mätt; mörkt läge är härlett enligt beslut 6.3.

### 2.1 Färger

```swift
enum StevenColor {
    // Ytor
    static let screen        = Color(hex: 0xFAFAFB)  // flikskärmar (01, 04, 05)
    static let content       = Color(hex: 0xF9F9FA)  // gruppens innehållsyta (08–10)
    static let surface       = Color.white           // kort, listrader, ark, footer, tab bar
    static let hairline      = Color(hex: 0xDBDBDD)  // linje under flikar, rad-separatorer (~#EDEDEF i listor)
    static let pressed       = Color(hex: 0xF4F4F5)  // markerad rad (05 "Uppgradera")

    // Text
    static let ink           = Color(hex: 0x3A3C4A)  // rubriker, belopp, vald flik
    static let inkSoft       = Color(hex: 0x4B4D5B)  // värden i Mina detaljer, flikrubriker (#4A4D5C)
    static let muted         = Color(hex: 0x9FA1AC)  // "N vänner", "De är skyldiga"
    static let label         = Color(hex: 0xACADB2)  // etiketter i formulär (07)
    static let section       = Color(hex: 0x7D7E85)  // SEKTIONSRUBRIKER
    static let faint         = Color(hex: 0xC8C9CE)  // "Carl betalade", tidsstämplar (#C4C4C9)
    static let tabInactive   = Color(hex: 0xA2A2A2)  // inaktiv flik + flikrubrik (#AAAAAA)
    static let placeholder   = Color(hex: 0xC5C5C7)  // "0" i beloppet

    // Accent — Steven: teal. Slice: blå (se 4.1)
    static let accent        = Color(hex: 0x1A75B8)  // Steven #1CB7A7 — text, länkar, konturknappar, Kvitt, positiva saldon
    static let accentFill    = Color(hex: 0x4FA9E8)  // Steven #1ADDC4 — FAB, fyllda knappar
    static let accentBright  = Color(hex: 0x4FA9E8)  // Steven #24E6D3 — "De är skyldiga"-beloppet i grupplistan
    static let accentDisabled = Color(hex: 0xA9D3F3) // Steven #8DDBD3 — avstängd Nästa
    static let accentTint    = Color(hex: 0xDCEEFB)  // Steven #D1F0ED — utgiftsikon "du betalade", info-ikonens cirkel

    // Riktning
    static let owe           = Color(hex: 0xFECCB5)  // korall: "Du är skyldig", negativa saldon
    static let oweTint       = Color(hex: 0xFFF5F0)  // utgiftsikon "någon annan betalade"
    static let unread        = Color(hex: 0xFEEFE8)  // oläst notis
    static let badge         = Color(hex: 0xFF383C)  // flikbadge
    static let chip          = Color(hex: 0xEBEBEC)  // kategorichip

    // Avatar-plattor (initialer), valda stabilt per medlem
    static let avatarPastels: [Color] = [
        Color(hex: 0xD4FAF6), Color(hex: 0xE9E5D3), Color(hex: 0xFFEBE1),
        Color(hex: 0xFDE3EF), Color(hex: 0xE2E9F3), Color(hex: 0xE4F6FE), Color(hex: 0xFFF6D9),
    ]
}
```

Korallen #FECCB5 har låg kontrast på vitt (≈1.5:1). Steven använder den så och vi behåller
den för att likna Steven. Riktningen bärs alltid också av ord ("Du är skyldig") och tecken
(−), så färgen är aldrig ensam bärare av betydelsen (#139).

### 2.2 Typografi

Steven använder en geometrisk grotesk. Vi använder SF Pro (systemtypsnittet) med Dynamic Type
och matchar vikter och storlekar vid standardstorleken (Large):

| Token | Storlek/vikt | Används till | Text style |
|---|---|---|---|
| `screenTitle` | 28 semibold | "Grupper", "Notiser" | `.title` |
| `groupTitle` | 26 bold | gruppnamn + total i gruppvyn | `.title` |
| `cardTitle` | 22 bold | gruppnamn på kort, profilnamn | `.title2` |
| `amountHero` | 64 heavy, monospacedDigit | beloppsinmatning | `.largeTitle` skalad |
| `navTitle` | 17 bold, versaler, kerning 0.5 | "INSTÄLLNINGAR", "UTGIFT" | `.headline` |
| `rowTitle` | 17 regular | listrader, namn | `.body` |
| `rowTitleBold` | 17 bold | utgiftstitel, belopp, "Kvitt" | `.headline` |
| `footnote` | 15 regular | datum, sekundärt | `.subheadline` |
| `footnoteBold` | 15 bold | utgiftskortets fotrad | `.subheadline.bold()` |
| `tab` | 15 bold, versaler | UTGIFTER/STÄLLNING | `.subheadline` |
| `section` | 15 regular, versaler | sektionsrubriker | `.subheadline` |
| `keypad` | 28 regular | knappsatsen | `.title` |

Alla belopp använder `monospacedDigit()` och svensk formatering: "53 545,08 kr" (mellanslag
som tusentalsavgränsare, komma som decimaltecken, decimaler bara när de inte är ,00) **[bild]**.

### 2.3 Avstånd, radier, skuggor

```swift
enum StevenMetric {
    static let gutter: CGFloat = 16        // sidmarginal överallt
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 12
    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6  // knappar, chips, inmatningsfält, kryssruta
    static let rowHeight: CGFloat = 60     // listrader (Mer, Inställningar)
    static let formRowHeight: CGFloat = 55 // Mina detaljer
    static let buttonHeight: CGFloat = 50  // Spara, LOGGA UT
    static let outlineWidth: CGFloat = 1.5
    static let fab: CGFloat = 60
    static let avatarStack: CGFloat = 38, avatarStackOverlap: CGFloat = 4
    static let avatarRow: CGFloat = 40, avatarHeader: CGFloat = 44, avatarHero: CGFloat = 70
    static let iconCircle: CGFloat = 44
    static let tabUnderline: CGFloat = 3
}
// Kortskugga: svart 10 %, radie 3, y 1. FAB: svart 15 %, radie 8, y 3. Footer: svart 6 %, radie 6, y −2.
```

### 2.4 Ikoner

Konturikoner med 1.5 pt linje (SF Symbols i `.light`/`.regular`). Tab bar: `person.2` /
`person.2.fill`, `bell` / `bell.fill`, `ellipsis`. Listrader: `person.badge.plus`, `link`,
`archivebox`, `rectangle.portrait.and.arrow.right`, `questionmark.square`, `info.circle`,
`square.and.arrow.up`. Utgift: `doc.plaintext` (kvitto). Chevron `chevron.right` i 17 pt light,
`chevron.left` i nav 24 pt light, `xmark` 24 pt light.

### 2.5 Delade komponenter (en per byggsten, alla i `ios/App/Steven/`)

| Komponent | Bild | Beskrivning |
|---|---|---|
| `StevenCard` | 01, 08, 09 | vit, radie 8, skugga, padding 16 |
| `AvatarView(member:size:)` | överallt | foto eller initialer på pastell; vår avatar/bild om den finns |
| `AvatarStack(members:size:overlap:)` | 01, 11 | överlappande rad, du först |
| `ScreenHeader(title:action:)` | 01, 04 | stor vänsterrubrik + accentaction med `+` |
| `NavTitleBar(title:leading:trailing:)` | 07, 11, 12, 15 | versal centrerad titel, `‹`/`✕`, accent-textknapp |
| `UnderlineTabs(selection:)` | 08–10 | jämnbreda versala flikar med accentlinje |
| `SectionHeader(_:)` | 06, 08, 11 | versal grå rubrik + hårlinje |
| `ListRow(icon:title:trailing:)` | 05, 06, 11 | 60 pt, ikon, text, `›`/toggle/värde |
| `FormRow(label:value:)` | 07 | etikett vänster, värde höger |
| `OutlineButton` / `FilledButton` | 01, 07, 08, 14 | radie 6, accent |
| `FAB` | 08 | 60 pt fylld cirkel med `+` |
| `BalanceFooter` | 08–10 | vänster saldo, höger action, FAB centrerad |
| `BalanceLabel(state:)` | 01 | "De är skyldiga X" / "Du är skyldig X" / "Kvitt" |
| `MoneyText` | överallt | svensk formatering, monospaced, färg efter riktning |
| `StevenTabBar` | 01, 04, 05 | 3 flikar (6.1) med badge |
| `Keypad` | 12, 13 | 3×4 rutnät, `,`, ⌫ |
| `ChipRow` | 14 | horisontella kategorichips + `…` |
| `CheckBox` | 14 | rundad accentruta med vit bock |
| `InfoCard(title:subtitle:)` | 10 | `i`-cirkel + två rader |

---

## 3. Beteenden och flöden

### 3.1 Lägg till utgift
1. Grupp → FAB `+` → ark steg 1. Betalare är som standard du, valutan gruppens primära **[bild]**.
2. Siffror via knappsatsen. `,` ger decimaler (max 2) och ⌫ raderar. Beloppet hålls som en
   heltalssträng i minor units; aldrig Double (CLAUDE.md, pengar).
3. "Carl betalade ›" byter betalare **[gissning: ark med medlemslista]**. "SEK ›" byter valuta
   (befintlig valutaväljare restylad).
4. Räknaren (+−×÷) gör en uträkning i beloppsfältet **[gissning]**; galleri och kamera tas bort (4).
5. Nästa (aktiv när beloppet > 0) → steg 2: beskrivning, kategori, deltagare och datum.
6. Standard: alla bockade, lika delning **[bild 50/50]**. Avbockning fördelar om lika. Ett ändrat
   procentfält gör fördelningen anpassad; "Återställ till att dela lika" återställer.
   Avrundning sker en gång vid skapande enligt Core (sorterat på memberId, resten fördelas uppifrån).
7. Spara → `LedgerStore.record(ExpenseCreated)`, arket stängs och utgiften syns överst under rätt månad.

### 3.2 Redigera eller ta bort utgift
Tryck på utgiftskortet → detalj (15) → Ändra → steg 2 med värdena ifyllda **[gissning: steg 1 nås
via beloppet]**. Spara skriver `ExpenseUpdated`. Ta bort ligger längst ner i redigeringen och
kräver bekräftelse **[gissning]**.

### 3.3 Göra upp / betala
Steven-bilderna visar bara Påminn. Vår M8-modell (Swish-länk, betalning före bekräftelse,
väntande status, bekräfta/bestrida, autobekräftelse efter 7 dagar) **behålls**. Den får bara
Steven-formen enligt beslut 6.4.

### 3.4 Skapa och gå med i grupp
- "Ny grupp +" → ark **[gissning, Steven-stil: NavTitleBar "NY GRUPP", namnfält, Spara]**. Gruppen
  skapas med bara dig i (CLAUDE.md). Därefter landar man i den nya gruppen, där tom-läget erbjuder
  "Grupplänk" **[gissning]**.
- Gå med: `slice://invite/<token>` öppnar den befintliga join-sheeten, restylad **[gissning]**.
- Inställningar → Lägg till medlemmar = lägg till person med namn (vännen som aldrig installerar,
  MembersSheet, får inte tas bort). Grupplänk = dela inbjudningslänk.

### 3.5 Arkivera och lämna
- Arkivera: swipe vänster på kortet eller Inställningar → Arkivera grupp. **Enhetslokalt**
  (UserDefaults: mängd av arkiverade GroupID), inget event. Arkiverade grupper syns under
  VISA ARKIVERADE och kan avarkiveras där **[gissning]**.
- Lämna: Inställningar → Lämna grupp → bekräftelse → `MemberRemoved` för dig själv (eventet
  finns redan). Bara tillåtet när ditt saldo är noll i alla valutor **[gissning]**.

### 3.6 Notiser
Härleds lokalt ur ledgern (befintliga `ActivityView`/`UnreadStore`). Notiser visas för andras
händelser som rör dig: utgift där du deltar, betalning till eller från dig, ny medlem, och
väntande bekräftelse. "Läs alla" nollställer. Tryck öppnar händelsen **[gissning]**. Inga
push-notiser (APNs är blockerat).

---

## 4. Avvikelser från Steven

Allt som inte står här ska följa Steven.

### 4.1 Brand
- **Accent: blå i stället för teal.** Ytor och fyllningar (FAB, fyllda knappar och "De är
  skyldiga"-beloppet) använder ikonens blå #4FA9E8. Text, länkar och konturer använder en mörkare
  blå #1A75B8, eftersom #4FA9E8 bara har ≈2.6:1 kontrast mot vitt och text kräver minst 4.5:1
  (#139). Stevens teal ligger på ungefär samma låga kontrast; detta är vår enda medvetna
  förbättring.
- **Appikon:** blå pizza (oförändrad, `docs/brand/slice-mascot.png`).
- **Namn:** "Slice" där Steven skriver "Steven" ("ta bort mitt Slicekonto").

### 4.2 Bilder
- **Gruppbanner:** gruppens foto (`GroupImageStore`) bakom gruppens huvud (6.2).
- **Avatarer:** medlemmens foto om det finns, annars initialer på Steven-pastell.

### 4.3 Steven-funktioner som tas bort (ingen motsvarighet, ingen datamodell)
Konto-fliken och plånboken, Stevenkortet, Fyll på pengar, Prenumerationer, Uppgradera mitt
konto och uppgraderingsbrickor, Göm erbjudanden, Bankanslutningar och "Dela transaktioner från
din bank", Skapa en säkerhetskod, Bekräfta betalningar med Face ID, Chatta med oss,
Återkommande utgifter/Upprepa, galleri- och kamerabilaga på utgifter, adress och e-post i Mina
detaljer, samt Betygsätt i App Store (tills appen finns där).

### 4.4 Slice-funktioner som behålls (i Steven-form)
| Funktion | Var i Steven-strukturen |
|---|---|
| Flera valutor, per-valuta-saldon, ≈-konvertering | valutachip i steg 1; saldon visas per valuta i footer och kort (en rad per valuta) |
| Swish/MobilePay, tvåsidig gör-upp (M8) | footerns Betala-knapp, STÄLLNING-utfällning och BETALNINGAR-fliken |
| Telefonnummer för betalning | Mina detaljer → Telefon |
| Påminnelser (lokala notiser) | Mer → Påminnelser |
| Utseende ljust/mörkt/system (#143) | Mer → Utseende |
| Statistik/rapporter, CSV-export | Inställningar → Statistik; Exportera i Statistik |
| Saldorevision (BalanceAuditSheet) | STÄLLNING → utfälld rad → "Så räknas det" |
| Offline/sync-status | diskret rad i Mer + fel som banner där de uppstår (oförändrat beteende) |
| Utvecklarverktyg (server, trial-nyckel) | Mer → Utvecklarverktyg |
| Svensk text | allt på svenska, även där Steven skriver engelska ("Save", "added you to") |

---

## 5. Diff mot nuvarande app

Läget 2026-10-20 (`08cb7ea`). Ingen eventtyp, payload eller sync-väg ändras. `ExpensePayload`
har redan `categoryId`, `date` och `payers`, så kategori- och datumväljaren är ren UI.

### 5.1 Struktur
| Nu | Steven-Slice |
|---|---|
| Egen flytande nav (`PhoneNavigationBar`): Översikt · Grupper · gul + · Ställning · Profil | Vit tab bar enligt 6.1. Ingen global +; utgifter läggs till från gruppen (FAB) |
| Översikt (`OverviewView`) med veckodiagram, aktivitet och rapportpiller | **Bort** (se 6.1). Saldon per grupp syns på grupplistan |
| Ställning-fliken (`PositionView`, `RelationshipDetailView`) | **Bort** som flik; ställning finns per grupp (STÄLLNING-fliken) |
| Profil (`JagView`, `PaymentServicesView`) | **Mer** + **Mina detaljer** |
| Notiser som ark från Översikt, ingen badge | **Notiser-flik** med badge från `UnreadStore` |
| `GroupPickerSheet`, `startAddExpense` | **Bort** (FAB sitter i gruppen) |
| iPad `.sidebarAdaptable` | Behålls; samma flikar |

### 5.2 Per skärm
| Skärm | Finns nu | Ändras | Nytt | Bort |
|---|---|---|---|---|
| Grupper | `HomeView`: lila bakgrund, staplad kortlek, sök | vita kort i lista, avatarstapel, saldorad | swipe-arkivera, VISA ARKIVERADE, "N vänner" | lila tema, kortlek, sökfält, profilknapp, `GroupBadge` som huvudelement |
| Grupp | `GroupDetailView` + `GroupSpendingView`: segment i bottenbar, korall-panel, diagram, "Gruppinformation" | huvud (namn+total+avatarer), 3 understrukna flikar, fast saldofooter + FAB | stjärnbricka, månadssektionerade kort med tonad ikon | veckopager, korallpanel, diagram (flyttas till Statistik), `GroupHeroCard`-disclosure |
| STÄLLNING | `PendingPaymentsCard`, `TransfersCard`, `MembersCard`, historik | medlemskort med ±saldo och utfällning | utfällning med par-skulder + Betala/Påminn + "Så räknas det" (`BalanceAuditSheet`) | separata kort |
| BETALNINGAR | `GroupRepaymentHistory` | lista i Steven-kort + info-kort | "Så här beräknar vi betalningar"-ark | |
| Gruppinställningar | toolbar-meny → `MembersSheet`, CSV | push-skärm i Steven-lista | Statistik-rad, Arkivera, Lämna, Grupplänk-rad | |
| Ny utgift | `NewExpenseSheet`: allt på en skärm + `SplitEditorSheet` med 4 lägen | två steg: belopp → detaljer | betalarchip, kategorichips, datumväljare, räknare, procentfält per rad, kryssrutor | gruppmeny i arket, `SummaryRow`, 4-lägesrutnät |
| Utgiftsdetalj | `ExpenseDetailSheet`: glyph, SharesCard, HistoryCard, Redigera/Ta bort | centrerad betalare, deltagarlista, fotnot | "Ändra" i nav | |
| Gör upp | `SettleUpSheet` + `SlideToConfirm` (M8) | restylad till Steven-ark | | slidens mint-kapsel blir accent |
| Ny grupp / Gå med | `NewGroupSheet` (emoji-rad, valuta), `JoinGroupSheet` | Steven-ark | | |
| Notiser | `ActivityView` ark, dagsgrupperat | flik, kort med oläst-ton, "Läs alla" | badge | |
| Mer | `JagView` | Steven-lista med profilhuvud | Dela till en vän, Hjälpcenter (→ `how-slice-works`), Om appen | tiltade betaltjänst-kort |
| Mina detaljer | `ProfileEditorView` | Steven-formkort | | |
| Statistik | `ReportsView` (5 sidor, mint/lila) | nås från Inställningar → Statistik, Steven-ytor | | editorial-färger |

### 5.3 Designsystem
- **Bort:** `Editorial`-paletten (coal/mint/purple/coral/yellow), `AvenirNextCondensed`-rubriker,
  `EditorialHeading/Pill/Panel/CardStack/Metric/Badge`, `cardSurface` radie 26, `PrimaryButtonStyle`
  i mint, `PhoneNavigationBar`, `AmbientBackground`, `GroupTint`s varma neutraler, ivory `bg`.
- **Ersätts av:** tokens och komponenter i avsnitt 2, i `ios/App/Steven/`.
- **Tester att hålla gröna:** `AppearanceContrastTests` (uppdateras till nya tokens),
  `GroupTintTests` (uppdateras till avatar-pastellerna), `PluralCopyTests` ("N vänner"),
  `SplitPreviewTests`, `ActivityScopeTests`, `ExpenseReportTests`, `StoreTests`.
- Strängar ligger kvar i `Localizable.xcstrings` (sv som källa, en-översättning).

---

## 6. Beslut (Carl, 2026-10-20)

- **6.1 Flikar: Grupper · Notiser · Mer.** Konto, Översikt och Ställning försvinner som flikar.
  Saldon syns per grupp på grupplistan och i gruppens STÄLLNING-flik.
- **6.2 Gruppbanner: bakom gruppens huvud.** I gruppvyn ligger gruppens foto 180 pt högt bakom
  namn, total och avatarer, med mörk toning nedtill (text vit på bild, annars som Steven).
  Ingen bild ger rent Steven-huvud. Grupplistans kort förblir rena Steven-kort. Tryck på bannern
  öppnar `GroupPhotoViewer`.
- **6.3 Mörkt läge: behåll Ljust/Mörkt/System (#143).** Mörka tokens härleds från samma roller:
  `screen` #121214, `content` #17171A, `surface` #1F1F23, `ink` #F2F2F5, `muted` #8E909B,
  `hairline` #2E2E33. Accent och korall behålls (accent-text #6BB8EE i mörkt för kontrast).
  Pastellplattor blir 25 % opacitet på `surface`.
- **6.4 Gör upp: Betala + Påminn via delning.** Är du skyldig visar footern "Du är skyldig X" och
  en fylld **Betala**, som öppnar befintliga `SettleUpSheet` (Swish/MobilePay, M8: väntar →
  bekräftad/bestriden, autobekräftelse efter 7 dagar) i Steven-stil. Är de skyldiga dig visar den
  "De är skyldiga X" och en konturknapp **Påminn**, som öppnar systemets delningsark med ett
  färdigt meddelande ("Hej! Du är skyldig mig 676,55 kr i Vårt äktenskap. Swisha gärna till
  070-123 45 67 🙂"). Är allt kvitt visar den "Kvitt" och ingen knapp. Samma Betala/Påminn finns
  per par i STÄLLNING-utfällningen. Flera valutor ger en rad per valuta, och knappen gäller den
  första öppna.
