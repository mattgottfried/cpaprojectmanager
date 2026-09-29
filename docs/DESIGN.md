# DESIGN.md

A portable SwiftUI design system, extracted from ThrillTrack (a native iOS app). Paste this into
a new project's context (alongside its own CLAUDE.md) so a future Claude session builds UI in the
same visual language — clean, information-dense, native-feeling, no third-party UI kit.

This describes *how things look and behave*, not what the app does. Swap the semantic color
meanings and brand colors for the new app's domain; keep the structure, scale, and interaction
rules.

## Philosophy

- **Native first.** Pure SwiftUI + SF Symbols, system materials (`.regularMaterial`,
  `.ultraThinMaterial`), system colors (`Color(.systemBackground)`,
  `Color(.secondarySystemGroupedBackground)`). No custom UI framework, no SPM design-system
  dependency. The app should feel like it belongs on iOS, not like a cross-platform shell.
- **Information density over whitespace.** Cards pack a status indicator, a title, one context
  line, and one detail line — not one fact per screen. Real-time/utility apps are read at a
  glance, often one-handed, sometimes urgently.
- **Color carries meaning, never decoration.** Every color in the palette maps to a semantic
  state (good/caution/bad/info/neutral). Pick a new app's palette by assigning colors to its own
  states first, then use them consistently everywhere that state appears.
- **Everything glanceable is also correct for VoiceOver and Dynamic Type.** A colored badge is
  never the only signal — pair it with an icon or word. See Accessibility below.
- **Reuse system chrome.** Tab bars, nav bars, sheets, `Form`/`List` — don't reskin what iOS
  already does well. Spend custom design effort on the small number of data-forward components
  (below), not on rebuilding navigation.

## Color System

### Semantic colors (the actual meaning, reuse across any app)

| Meaning | Color | Example use |
|---|---|---|
| Good / short / success | `.green` | short wait, under budget, completed |
| Caution / medium | `Color(red: 1, green: 0.75, blue: 0)` (a warmer orange-yellow than system `.orange`) | medium wait, approaching a limit |
| Bad / long / stop | `.red` | long wait, over budget, closed |
| Alert / needs attention now | `Color(red: 1, green: 0.55, blue: 0)` (a more saturated orange than caution) | down/broken, urgent heads-up |
| Info / neutral-but-notable | `.blue` | open with no data yet, informational badge |
| Unknown / disabled | `.gray` | no signal, not operating, disabled state |
| Delight / favorite / star | `.yellow` | favorited/starred/must-do marker |
| Money / stats accent | `.purple` | a secondary stat that isn't good/bad, just a number |

Keep a single pure function mapping a domain value to one of these, e.g.:

```swift
func statusColor(value: Int?, isActive: Bool, alert: Bool) -> Color {
    if alert { return .orange }          // the more saturated alert orange
    guard isActive else { return .gray }
    guard let v = value else { return .blue }
    if v < lowThreshold { return .green }
    if v < highThreshold { return .yellow /* caution orange-yellow */ }
    return .red
}
```
Never inline the color logic at each call site — one function, reused everywhere a status badge
appears (list row, detail header, map pin, widget).

### Brand / section theming

If the app has more than one "mode" or brand context (different resorts, different workspaces,
different account tiers), define one small theme struct and switch on the mode:

```swift
struct AppTheme {
    let primaryColor: Color        // brand color for headers/tab tint
    let accentColor: Color         // secondary brand color, used sparingly
    let cardBackground: Color      // Color(.systemBackground) or Color(.secondarySystemGroupedBackground)
    let cardShadowOpacity: Double  // 0.08 for a light card background, 0.0 when the background is already elevated
    let preferredColorScheme: ColorScheme
}
```
Real values used in ThrillTrack (for calibration, not to copy verbatim):
- Light-background brand: primary a deep navy (`0,60,113`), accent a gold (`253,185,19`), card
  background `.systemBackground`, shadow opacity `0.08`, light scheme.
- Dark-background brand: primary near-black (`20,20,20`), accent a bold gold (`252,190,17`), card
  background `.secondarySystemGroupedBackground` (already dark, no shadow needed), shadow opacity
  `0`, dark scheme.

The pattern: light-mode brands get a real shadow under white cards; dark-mode brands skip the
shadow because the card background already reads as "raised" against the system dark background.

## Typography

Use Apple's text styles (`.headline`, `.subheadline`, `.caption`, `.title2`, …) almost
exclusively — never raw point sizes for body text, so Dynamic Type works automatically.

- **Card title**: `.body.weight(.semibold))`, `lineLimit(2)`, `fixedSize(horizontal: false, vertical: true)`
- **Section header inside a card**: `.headline`, tinted with the card's accent color
- **Subtitle / status line**: `.caption.weight(.semibold)`, tinted with its semantic color
- **Detail / secondary line**: `.caption`, `.foregroundStyle(.secondary)`
- **Big hero numbers** (a countdown, a large stat): use `@ScaledMetric` off a text style, not a
  bare `.system(size:)` — e.g. `@ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 24`.
  This keeps a deliberately large number in scale with the rest of the UI while still growing at
  larger accessibility text sizes instead of clipping.
- **Share-card / marketing-style headline**: `.title2.bold()` on a colored background, with a
  `.caption.weight(.semibold)` eyebrow line above it (see Gradient Share Card below).

## Spacing & Shape Scale

Two corner-radius scales, used consistently by role — don't invent new radii per screen:

| Radius | Role |
|---|---|
| 8–10 | small inline chips/icons inside a row (mini progress dots, small icon backgrounds) |
| 12–14 | list-row cards (the everyday repeating card) — `RoundedRectangle(cornerRadius: 14, style: .continuous)` |
| 16 | section/dashboard cards (`statsCard`-style, see below) |
| 22 | large "hero" cards — a shareable summary card, a big feature callout |
| `Capsule()` | any pill/badge — status labels, filter chips, toast |

Padding: card interiors use `.padding()` (system default, ~16pt) for dashboard cards, and
`.padding(.horizontal, 12).padding(.vertical, 10)` for denser list-row cards. Row internal spacing
is `8–12` between elements, `4–6` between stacked text lines.

## Core Components

### 1. Status Tile
A small square/rounded-square tile that is the *first* thing the eye hits in a row — a number,
an icon, or a short status word, colored by the semantic status function above.

```swift
struct StatusTile: View {
    let value: Int?          // nil when there's no number to show
    let isActive: Bool
    let alert: Bool
    var size: CGFloat = 58
    var numberSize: CGFloat = 24
    var unit: String = ""    // "min", "%", etc — shown under the number in a smaller caption

    var color: Color { statusColor(value: value, isActive: isActive, alert: alert) }

    var body: some View {
        VStack(spacing: 0) {
            if isActive, let value {
                Text("\(value)").font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.caption2.weight(.semibold)).opacity(0.8) }
            } else if alert {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: numberSize * 0.8))
            } else {
                Image(systemName: "xmark").font(.system(size: numberSize * 0.8, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
        .accessibilityHidden(true)  // the parent row supplies one combined accessibility label/value
    }
}
```
Optional corner badge: an overlay circle (≤20% of tile size) at `.topTrailing` for a secondary
signal (e.g. a trend arrow) — white icon on a small solid-color circle, `.offset(x: 4, y: -4)`.

### 2. List-Row Card
The everyday repeating row: tile + text stack, one optional colored outline for a "featured"
state, an opacity dim for an inactive/closed state.

```
HStack/VStack(alignment: .leading, spacing: 12) {   // VStack at accessibility text sizes
    StatusTile(...)
    VStack(alignment: .leading, spacing: 4) {
        HStack { Title().lineLimit(2); Spacer(); optional star/favorite icon }
        if let subtitle { Label(subtitle, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color) }
        if hasDetails { detail row — small icons + short text, .caption, .secondary }
    }
}
.padding(.horizontal, 12).padding(.vertical, 10)
.background(theme.cardBackground)
.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
.overlay { if featured { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.green.opacity(0.6), lineWidth: 1.5) } }
.shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
.opacity(isActive ? 1.0 : 0.6)
```
**Accessibility on every card**: `.accessibilityElement(children: .ignore)` +
`.accessibilityLabel(title)` + `.accessibilityValue(statusText)` +
`.accessibilityHint(whatTappingDoes)` + `.accessibilityAddTraits(.isButton)`. Never let VoiceOver
read the tile and text as separate elements.

**Layout switch at accessibility text sizes**: swap `HStack` for `VStack` when
`dynamicTypeSize.isAccessibilitySize` so the tile doesn't squeeze the text:
```swift
let layout = dynamicTypeSize.isAccessibilitySize
    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
    : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
```

### 3. Dashboard/Section Card
A titled card for a hub screen (stats, settings sections) — icon + title header, then arbitrary
content:
```swift
func sectionCard<Content: View>(title: String, systemImage: String, color: Color,
                                @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Label(title, systemImage: systemImage).font(.headline).foregroundStyle(color)
        content()
    }
    .padding()
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
}
```

### 4. Stat Chip
A number + label pair, used in rows of 2–4 across the top of a stats/summary screen:
```swift
VStack(spacing: 3) {
    Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
    Text(label).font(.caption2).foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 6)
.background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
```

### 5. Badge / Capsule
Any small status pill (a filter chip, an inline flag like "Blocked Out" or "Offline"):
```swift
Label(text, systemImage: icon)
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.white)                 // or the semantic color, for a lighter pill (see below)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(color, in: Capsule())        // solid fill for a strong/urgent pill
```
A lighter/secondary pill uses a tinted background instead of a solid fill:
```swift
Label(text, systemImage: icon)
    .font(.caption.weight(.semibold))
    .foregroundStyle(color)
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(color.opacity(0.12), in: Capsule())
```
Use the solid-fill version for something urgent/rare (offline, blocked, closing soon); the
tinted version for a normal, frequent status (a category label, a level indicator).

### 6. Gradient Share Card
A shareable/highlight card meant to stand alone as an image (a recap, a summary someone screenshots
or shares) — richer color than the rest of the app, dark gradient background, white text:
```swift
VStack(alignment: .leading, spacing: 14) {
    VStack(alignment: .leading, spacing: 2) {
        Text(eyebrow).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
        Text(headline).font(.title2.bold()).foregroundStyle(.white)
    }
    HStack(spacing: 10) { /* 2-3 StatBlocks, see below */ }
    VStack(alignment: .leading, spacing: 8) { /* Label() lines, .white, .subheadline.weight(.medium) */ }
    HStack { Spacer(); Text(appName).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6)) }
}
.padding(18)
.frame(maxWidth: .infinity, alignment: .leading)
.background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
```
StatBlock inside it (semi-transparent white tile on the gradient):
```swift
VStack(alignment: .leading, spacing: 2) {
    Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.7))
    Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
        .lineLimit(1).minimumScaleFactor(0.6)
    Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
}
.frame(maxWidth: .infinity, alignment: .leading)
.padding(10)
.background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
```
Render to a shareable image with `ImageRenderer` at `scale = 3`, and always also offer a
plain-text `ShareLink` alternative for anyone who'd rather paste text than an image.

### 7. Round Icon Toolbar Button
Icon-only buttons floating over a map or full-bleed content:
```swift
Button { action() } label: {
    Image(systemName: name).font(.body.weight(.medium)).padding(8)
        .background(.regularMaterial, in: Circle())
}
.accessibilityLabel("What this button does, as a full phrase")
```
Always material-backed (`.regularMaterial`), never a flat color square — this is what makes an
icon button float legibly over a photo/map background in both light and dark mode.

### 8. Empty State
Use `ContentUnavailableView` with a real call-to-action, never a bare "No items" label:
```swift
ContentUnavailableView {
    Label("No [things] yet", systemImage: symbolName)
} description: {
    Text("One sentence on how to get your first one.")
} actions: {
    Button("Do the thing") { ... }.buttonStyle(.borderedProminent)
}
```

### 9. Undo Toast
A floating capsule for "deleted — undo?", not a modal alert:
```swift
HStack(spacing: 12) {
    Image(systemName: "trash").foregroundStyle(.secondary)
    Text(message).font(.subheadline).lineLimit(1)
    Spacer(minLength: 8)
    Button("Undo") { undo() }.font(.subheadline.weight(.semibold))
}
.padding(.horizontal, 16).padding(.vertical, 12)
.background(.regularMaterial, in: Capsule())
.shadow(color: .black.opacity(0.15), radius: 8, y: 2)
.padding(.horizontal, 16)
.transition(.move(edge: .bottom).combined(with: .opacity))
.sensoryFeedback(.impact(weight: .light), trigger: message)
```
Pattern: delete immediately (optimistic), show this toast ~4 seconds, re-insert on Undo. Never a
confirmation dialog before a delete that's this easy to undo.

## Interaction Rules

- **Haptics via `.sensoryFeedback`**, never `UIFeedbackGenerator` directly:
  - `.selection` — a filter/tab/segment changes
  - `.success` — a save, a completed action, a manual refresh finishing
  - `.warning` — something the user should notice went wrong (a down/alert state appearing)
  - `.impact(weight: .light)` — a toast/notification-style appearance
- **Context menus** on list-row cards for secondary actions (favorite, add-to, set-alert,
  details) instead of swipe actions when there are more than 2 actions; reserve swipe actions
  for the single most common action (done/delete).
- **Sheet detents**: `.medium` for a short/inline sheet reached from a card (compact context),
  `.large` for a primary flow the user came here to do, `[.medium, .large]` when the content
  genuinely grows (e.g. a list that can be short or long).
- **`TimelineView(.periodic(from:by:))`** for anything that needs to re-render on its own as time
  passes (a countdown, a "5 min ago" staleness label) — don't hand-roll a `Timer` + `@State`.
- **Optimistic, reversible actions** over confirmation dialogs wherever the action is cheap to
  undo (see Undo Toast). Reserve `.confirmationDialog` for genuinely destructive, hard-to-reverse
  actions (a full reset, not a single row delete).

## Accessibility (non-negotiable, not a phase-2)

- Every custom row/tile is one combined accessibility element with a real label + value + hint,
  never left to VoiceOver to piece together from child views.
- Status is never color-only — every colored badge has a word or icon alongside it.
- Icon-only buttons always get `.accessibilityLabel` as a full phrase ("Show my location", not
  "Location").
- Hero numbers scale with `@ScaledMetric`; body text uses text styles, never fixed point sizes.
- Test the accessibility text size (AX5) on every new screen — check for clipped numbers and
  layout that should switch to a vertical stack.

## Dark Mode

- Prefer system dynamic colors (`Color(.systemBackground)`, `.secondary`, `Color(.systemFill)`)
  over hardcoded light/dark pairs — they're correct for free.
- A brand that's inherently dark (see Brand Theming above) should set
  `preferredColorScheme: .dark` for that section/mode rather than fighting a light system theme
  with dark custom colors.
- Semantic status colors (`.green`/`.red`/`.orange`/`.yellow`/`.blue`) already adapt across light
  and dark automatically — don't override them per-scheme.

## Iconography (SF Symbols conventions)

- One consistent symbol per recurring status across the whole app (don't let "closed" use
  `xmark` in one screen and `slash.circle` in another).
- Filled variants (`.fill`) for anything that's "on"/active/positive; outline variants for
  neutral/available/inactive. A toggle button shows the filled symbol only in its active state
  (e.g. `parked ? "car.fill" : "car"`).
- A badge's icon should be legible at `caption2` size — avoid symbols with fine detail for small
  badges; save detailed symbols for headline-size icons.

---

*Extracted from ThrillTrack, a SwiftUI iOS app (native, no third-party UI dependencies, iOS 17+,
`@Observable`, SwiftData). The concrete component code above is real, working SwiftUI — adapt
names and semantic color assignments to the new app's domain, keep the shapes, scale, and
interaction rules.*
