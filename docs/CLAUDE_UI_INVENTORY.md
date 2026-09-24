# Phase 0 — Reference inventory and component specification

Deliverable for the Claude mobile UI/UX clone layer: every screen and widget
observed in the reference material, what it is made of, and how it behaves.
No widget was written before this document was finished.

---

## 1. Sources actually used, and what each one is worth

| # | Source | Status | Used for |
|---|---|---|---|
| 1 | User-provided screenshots | **Not received.** The session arrived with prompt text only; no image files were attached (confirmed with the user, who asked to proceed on the store references). | — |
| 2 | App Store listing, `id6473753684` | Fetched; 9 iPhone screenshots resolved through the iTunes lookup API at 392×696 and inspected individually. | Light-mode chat surface, top bar, user bubble, composer, streaming row, markdown rendering |
| 3 | Play Store listing, `com.anthropic.claude` | Fetched; 8 screenshot URLs resolved, plus Play's own description of the surface. | Android-specific checks (no bottom nav, no FAB, same top bar) |
| 4 | `shadcn.io/design/claude/raw` | Fetched in full (DESIGN.md, 5 chunks). | Colour, type, radius, spacing and motion tokens |
| 5 | Page Flows Android captures (`/post/android/chat-bot/claude`, `/settings`, `/licenses`) | Fetched; 5 real device screenshots downloaded and inspected, including pixel sampling. | Android home screen structure, settings list, licence list, measured canvas |
| 6 | Design critique (IXD @ Pratt) | Read in full. | *Why* the home screen is ordered the way it is; the affordance argument for the composer cluster |
| 7 | Image searches (8 queries, all run) | 40 images saved and reviewed. Most returned the web product rather than the mobile app; the Android app captures in §5 were the useful hits. | Cross-checks only |
| 8 | `claude.com` MCP Apps design guidelines | Fetched in full. | Component patterns, spacing discipline, the anti-pattern list (no deep navigation, no nested scrolling, no menus where visible controls will do) |
| 9 | Lazyweb `/company/claude` | Fetched; the page exposes only 5 of its 46 screens without an account, and they are paywall-flow screens. | Paywall/settings row patterns |

### Reference conflicts, and how they were resolved

1. **Canvas colour.** The 2024 Android capture (Page Flows) measures
   `rgb(239,239,227)` — a softer, greener cream. The current iOS App Store
   screenshots measure `rgb(249,248,244)`, i.e. `#FAF9F5`. The token document
   says `#FAF9F5`. **Resolution: `#FAF9F5`.** Two independent current sources
   agree and the third is a two-year-old build.
2. **User bubble fill.** Measured `rgb(241,238,231)` in the iOS capture against
   `surface-soft #F5F0E8` in the token document, a delta of 2–4 per channel —
   inside the error of a JPEG at 350 px wide. **Resolution: token
   `surfaceSoft`**, so the fill stays a named token rather than a sampled
   approximation.
3. **Home screen composition.** The brief specifies a centred mark + serif
   greeting + 2×2 suggestion chips. The current app instead puts the greeting
   and a couple of conversation cards above the composer (see §5). **Resolution:
   the brief wins** — it is the specification; the observed difference is
   recorded here so it is a decision, not an oversight.
4. **Accent colour.** The published brand coral is `#CC785C`. Sampling the
   compose button in the App Store capture gives `rgb(220,115,87)` (a JPEG of a
   40 px circle, so ±8 per channel). The capture is the *app's* accent, the
   token is the *marketing* accent, and they agree within measurement error.
   **Resolution: `#CC785C`**, because it is the named token and the sampled
   value cannot be distinguished from it on screen.

### Environment limits on this phase

`dl.google.com`, `pub.dev`, `fonts.googleapis.com`, `storage.googleapis.com`,
`play-lh.googleusercontent.com`, `is1-ssl.mzstatic.com`,
`raw.githubusercontent.com` and every image-resizing proxy are unreachable from
this sandbox; the storefront pages themselves were reachable and are the source
of the screenshot URLs above. There is no Flutter/Dart toolchain available
locally either, so verification runs through the repository's own CI
(`ci-test.yml`, Flutter 3.44.0) rather than a local `flutter analyze`.

---

## 2. Token set, cross-checked against pixels

Taken from the DESIGN.md "chat surface" tokens — not the marketing-surface ones
— and then verified against the captures. `#FAF9F5`, `#CC785C`, the 12 px card
radius and the flat-cornered buttons all survive that check.

| Token | Value | Evidence |
|---|---|---|
| `canvas` | `#FAF9F5` | Sampled `rgb(249,248,244)` in iOS capture 1 |
| `surfaceSoft` | `#F5F0E8` | Sampled `rgb(241,238,231)` for the user bubble (see conflict 2) |
| `surfaceCard` | `#EFE9DE` | Card fill on the Android home capture |
| `ink` | `#141413` | Sampled `rgb(33,33,21)`–`rgb(60,59,55)` for display and body text |
| `body` / `muted` / `mutedSoft` | `#3D3D3A` / `#6C6A64` / `#8E8B82` | Body, metadata, placeholder |
| `hairline` / `hairlineSoft` | `#E6DFD8` / `#EBE6DF` | 1 px borders, dividers |
| `primary` | `#CC785C` | Compose button, sampled `rgb(220,115,87)` (see conflict 4) |
| `primaryActive` | `#A9583E` | Pressed CTA |
| `surfaceDark` | `#181715` | Dark canvas, code-block surface in both modes |
| `surfaceDarkElevated` | `#252320` | Sheets and the sidebar in dark mode |
| `onDark` | `#FAF9F5` | Text on dark and on code blocks |
| `error` | `#C64545` | Destructive rows, engine failures |

Motion: `durationFast` 150 ms, `durationBase` 280 ms, `durationSlow` 500 ms;
`easeOut` ≈ `cubic-bezier(0.32, 0.72, 0, 1)`, which Flutter's `Curves.decelerate`
closely matches, plus `easeEmphasized` for sheet and sidebar travel.

Type: `display` 32 px, `heading` 24 px, `title` 20 px, `body` 16 px,
`bodySmall` 14 px, `caption` 12 px; body line-height never below 1.5
(the tokens use 1.55–1.65). Families: Lora for display copy, Lato for every
control and body run, JetBrains Mono for code — substituting for the licensed
Copernicus / Styrene B / same mono.

---

## 3. Component inventory

### 3.1 Top bar (chat) — 56 dp

Observed in every App Store capture.

- Left: 32 dp circular button, `canvas` fill on `canvas` with a subtle
  `hairline` edge, holding a back chevron (chat) or the menu glyph (home).
- Centre: model name at ~15 px, weight 500, in `ink`, followed by a chevron-down
  glyph. The whole cluster is one tap target that opens the model sheet.
- Right: 32 dp circle filled `primary` with a white compose/plus glyph.
- Bottom edge: 1 px `hairline`; below it, the message action row in streaming
  states.
- Tokens: height 56, side padding 12, gap 8.

### 3.2 Home / new chat

- Centred radial-spike mark, `primary`, ~44 dp.
- Serif greeting beneath it, ~28–32 px, weight 400, `ink`, centred, and
  time-of-day aware ("Good morning" / "How can I help you this evening" — the
  critique article confirms the greeting adapts to the time of day).
- Four suggestion chips in a 2×2 grid: `surfaceCard` fill, `hairline` border,
  12 dp radius, `body` text, 16 px side padding, min height 44 dp.
  **Ceiling: 2 lines of text** — see §4.
- Composer pinned to the bottom, floating on the canvas.
- Behaviour: chips fade in and rise 12 dp on a 60 ms stagger; the first
  keystroke in the composer fades all four out together; a tap fills the
  composer rather than sending.

### 3.3 Active chat

- User turn: right aligned, `surfaceSoft` fill, max 80 % of the pane width,
  12 h / 10 v padding, 18 dp radius with bottom-right dropped to 4 dp, `body`
  text in `ink`. Attached images render inside the bubble above the text.
- Assistant turn: **no bubble at all** — text sits on `canvas`. A 20 dp mark in
  the left gutter is aligned to the first line of the answer. Markdown renders
  fully: headings, lists, tables, block quotes, inline code.
- Code blocks: `surfaceDark` fill in both modes, `onDark` text, JetBrains Mono
  12.5 px, 12 dp radius, copy button top-right, horizontally scrollable, never
  wrapped.
- Action row under the final assistant message: copy, regenerate, and the
  in-message maths toggle (this app's own addition, kept — see §4). Fades in
  over 150 ms once generation completes.
- Streaming: a 1 dp `primary` cursor blinking on a 600 ms interval trails the
  last token; the send button becomes a stop button in place.

### 3.4 Sidebar

- Slides in from the left at 85 % of the screen width over 280 ms with the
  documented ease-out; black scrim at 40 % fades in behind it.
- Opens from the top-bar button, from a left-edge swipe, and closes on scrim
  tap, leftward swipe, or system back.
- Header: the app's own name and mark.
- "New chat" button: full width minus 16 dp each side, `primary` fill,
  `onPrimary` text at weight 500, **flat corners**, 44 dp tall.
- Search field: pill (24 dp radius), `surfaceSoft`/`surfaceDark` fill,
  `hairline` border, "Search conversations" in `mutedSoft`.
- Conversation list grouped by recency — Today, Yesterday, Previous 7 days,
  Older — with 12 px uppercase `muted` group headers. Rows are 52 dp: title at
  14 px weight 500 in `bodyStrong`, truncated to one line; timestamp at 12 px
  `mutedSoft` right aligned; an optional subject chip at 10 px on a 15 %
  `primary` wash. The active row gets a `hairlineSoft` fill.
- Swipe left reveals a 48 dp delete affordance; confirming collapses the row
  over 280 ms. The existing undo bar is kept (see §4).
- Footer: avatar circle (initial fallback), the app name, and a settings gear.

### 3.5 Composer (all chat screens)

- Floats directly on `canvas`. **No surface fill, no top border, no shadow** —
  the current implementation's elevated card with a `hairline` top border is
  the single largest visual difference from the reference and is removed.
- Left: 24 dp attach glyph in `muted`.
- Field: pill, 24 dp radius, `surfaceSoft` fill in light / a one-step elevation
  in dark, 1 px `hairline`, `body` text in `ink`, hint "Message Library AI" in
  `mutedSoft`. Grows to 5 lines then scrolls internally.
- Right: 32 dp circle — `primary` with an up-arrow when there is something to
  send, `hairline` fill when empty (disabled).
- Attachment preview: 64 dp thumbnail with an ×-dismiss, sliding down from the
  top over 150 ms.
- Bottom padding is the system inset plus 8 dp; the field never hides behind
  the keyboard (`resizeToAvoidBottomInset: true`).

### 3.6 Model switcher sheet

- `DraggableScrollableSheet`, initial 50 %, max 90 %, 16 dp top radius,
  `surfaceCard` (light) / `surfaceDarkElevated` (dark), 32×4 dp handle in
  `muted` 8 dp from the top.
- Title "Switch model" at 16 px weight 500.
- Rows: model name (Lato Medium, `bodyStrong`), a parameter-count chip, a vision
  badge when the projector is installed, and a state read-out (Active / Ready /
  Download). Downloaded-but-inactive rows get a `muted` check; the active row a
  `primary` check. Tapping a downloaded model closes the sheet and switches.

### 3.7 Settings

List on `canvas`, 12 px uppercase `muted` section headers, 56 dp rows, 1 px
`hairline` dividers, value/control right aligned. Sections: Appearance
(theme segmented control; chat font), AI Behaviour (default model, context
length, temperature, top-p, default system prompt), Storage (models, with the
existing SAF folder picker and per-model delete/export rows, conversations),
About (version, open-source licences, the on-device statement).

### 3.8 Empty and error states

The "no model installed" empty state, the engine-error card, the model-update
banner and the storage warning banner all stay — they are contract, not chrome.
They are restyled onto the token set and keep their current copy and actions.

---

## 4. Deliberate deviations, with reasons

Each of these is a place where following the reference literally would have
made the product worse. They are listed so the difference is a decision.

1. **Six suggestion chips would not fit a 2×2 grid on a 360 dp phone.** Chips
   are capped at two lines and the grid is a fixed 2×2; chips whose text would
   exceed that are not shipped. Copy is written short enough to fit:
   "Explain a hard idea", "Quiz me on a topic", "Summarise my notes",
   "Show the working".
2. **In-message maths toggle kept.** The reference has no such control because
   the hosted model always emits delimiters; a local GGUF sometimes does not.
   Removing it would strand the user with raw LaTeX, so the action row carries
   it.
3. **Delete-undo kept** in the sidebar alongside the swipe affordance. A swipe
   is easy to trigger by accident; the undo bar is the recovery path.
4. **Context meter lives in the top bar** as a 2 dp animated rule under the top
   bar's border, with a labelled read-out on long-press. The brief asks for it
   in the top bar; the composer must stay bare, so it cannot live there.
5. **No bottom navigation bar, no FAB, no shadows, no gradients, no second
   accent colour** — held to exactly, everywhere.

## 5. Screen → route map

| Reference screen | Implementation |
|---|---|
| Home / new chat | `ChatScreen` → `HomeView` when the thread is empty |
| Active chat | `ChatScreen` → `ChatView` + `ClaudeTopBar` + `MessageComposer` |
| Recents / sidebar | `ConversationSidebar` overlay in `ChatScreen` |
| Model switcher sheet | `ModelSwitcherSheet.show` |
| Persona picker sheet | `PersonaPickerSheet.show` |
| Settings | `SettingsScreen` (pushed route) |
| Model library | `ModelLibraryScreen` (pushed route) |
| Personas / notes | `PersonasScreen`, `NotesScreen` (pushed routes) |
| Attachment permission sheet | Camera-intent flow in `MessageComposer` |
