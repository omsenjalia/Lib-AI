# Library AI (React Native): Architecture

How the React Native app is put together, and why. The short version: one
SQLite file, one resident model, one place that talks to the network, and a
chat surface modelled on the Claude mobile app.

This app is a port of the Flutter build in `../lib`. The Flutter
[ARCHITECTURE.md](../ARCHITECTURE.md) is still the record of *why* most rules
exist (the checksum gate, the Wi-Fi block, "an update check can only ever
produce a badge"). This document covers how those rules live in TypeScript and
what changed in the move.

---

## 1. Stack, and what each choice replaced

| Concern | React Native | Flutter build | Why |
|---|---|---|---|
| Framework | Expo SDK 57, React Native 0.86, New Architecture, Hermes | Flutter 3.44 | Config plugins generate `android/`; nothing native is hand-edited |
| Navigation | `expo-router` (files in `src/app/`) | `Navigator` | Five screens; the drawer is a custom Reanimated view, not a navigator |
| State | `zustand` stores in `src/state/` | Riverpod | Plain modules with `getState()` for services, hooks for screens |
| Database | `expo-sqlite`, hand-written SQL in `src/core/db/` | drift | No codegen step; the schema is small and the queries are few |
| Inference | `llama.rn` 0.13 (llama.cpp, JSI) | `fllama` (pinned git ref) | Real load *and* release calls, `top_k`, `n_parallel`, OpenCL on Adreno |
| Downloads + hashing | `react-native-blob-util` | dio + `crypto` | Native streaming SHA-256, append-mode Range resume, per-request Wi-Fi binding, `df()` |
| Notifications | `expo-notifications` | flutter_local_notifications + a Kotlin service | See section 6.3 for what was lost |
| Markdown | `marked` lexer, rendered to native `Text` by `Markdown.tsx` | flutter_markdown | Inline maths and streaming behave exactly as designed |
| Code | `prism-react-renderer` tokens to native `Text` | flutter_highlight | Warm theme, no DOM |
| Maths | KaTeX HTML with bundled KaTeX fonts (display), Unicode (inline) | flutter_math_fork | Section 5 |
| PDF | `expo-print` (system WebView) + `expo-sharing` | `pdf` package | Real Unicode and typeset maths; the WinAnsi transliteration is gone |
| Motion | Reanimated 4 + Gesture Handler | one AnimationController | Section 7 |
| Icons | `phosphor-react-native` | Material icons | One stroke family, regular weight |

---

## 2. Layout and layering

```
mobile/
  app.json            Expo config + config plugins (llama.rn OpenCL/Hexagon, fonts, permissions)
  eas.json            cloud APK builds (no local JDK needed)
  assets/             fonts (OFL) and models_catalogue.json (copy of the root file)
  src/
    app/              routes: index (chat), library, settings, personas, notes
    components/
      chat/           TopBar, Sidebar, HomeView, MessageList, MessageRow, Composer,
                      Markdown, CodeBlock, MathBlock(.web), ThinkBlock, Sheets, Banners
      library/        ModelCard
      ui/             primitives (AppText, PressableScale, Button...), Sheet, Toast,
                      controls (Segmented, Slider, Toggle), Screen
    state/            zustand stores: settings, library, chat, collections, engineStatus, bootstrap
    core/             no React here
      engine/         InferenceEngine + backend.native.ts (llama.rn) / backend.web.ts (demo)
      db/             schema (migrations), database (all queries), events (change bus), types
      services/       downloadManager, updateChecker, files.native/.web, connectivity,
                      notifications, exporter, attachments, legacyImport
      utils/          latexSplitter, latexToText, markdownBlocks, tokenEstimator,
                      memoryBudget, formatters
      prompt.ts       prompt assembly and budgeting
      catalogue.ts    typed, validated view of the bundled catalogue
      settings.ts     preference keys, parsing, defaults
      errors.ts       AppError: message + detail + recovery advice
    theme/            tokens (light/dark palettes, type, motion), ThemeProvider
  __tests__/          jest: utils, splitter, engine, downloads, updates, prompt, catalogue, offline boundary
```

Rules that hold it together:

1. **`src/core` never imports React or a component.** Engine, downloads,
   updates and prompt logic take their dependencies as arguments, so tests
   construct them with fakes (`__tests__/engine.test.ts`,
   `__tests__/downloadManager.test.ts`).
2. **Screens talk to stores; stores talk to `core`.** A component never calls
   `react-native-blob-util` or `fetch`.
3. **Platform seams are files, not `if`s.** Metro resolves `files.native.ts`
   vs `files.web.ts` and `backend.native.ts` vs `backend.web.ts`. TypeScript
   follows the native side through `"moduleSuffixes": [".native", ""]`.
4. **Errors are values with advice.** `AppError` carries a `kind`, a
   user-facing `message`, an optional `detail` and a `recovery` line. Failed
   turns are written into the transcript with `toTranscript()`, so a failure
   survives a restart.

---

## 3. Inference

### 3.1 What llama.rn changed

The Flutter engine was shaped by fllama having **no load and no unload call**:
a 1-token warm-up to discover OOM, contexts reaped 120 s after last use, and a
hard-coded four parallel slots that quietly quartered every conversation's
context window. `llama.rn` removes all three constraints:

| Flutter (fllama) | React Native (llama.rn) |
|---|---|
| Warm-up turn to force the load | `initLlama()` *is* the load, with a progress callback |
| `unload()` waited for a 120 s reaper; switching briefly held two models | `context.release()` frees immediately; the old model is released before the next maps |
| 4 slots: an 8192 request gave a chat 2048 | `n_parallel: 1`: the chat gets the whole window (`AppConstants.parallelSlots`) |
| `top_k` persisted but never applied | `top_k` is applied |
| No Android GPU backend | OpenCL offload on Adreno 700+ when GPU layers > 0, with automatic CPU retry |

### 3.2 Load path (`core/engine/engine.ts`)

```
ensureModelLoaded()                         state/chat.ts
  ├─ active model: default if installed, else first installed
  ├─ context = conversation override ?? settings, clamped to the model's max
  ├─ memory preflight: /proc/meminfo MemAvailable (+ what the resident model frees)
  │     vs ramRequirementGbFor(installed quant) + KV for extra context, x1.15 headroom
  │     (the projector is not part of the load; see 3.3 step 4)
  └─ engine.load(request)                   serialised; same request joins, others queue
        ├─ verifying        file exists and is over 1 MB
        ├─ readingMetadata  loadLlamaModelInfo(): a truncated GGUF fails here, cheaply
        ├─ loadingWeights   initLlama({n_ctx, n_parallel: 1, n_gpu_layers, ctx_shift: !vision,
        │                             cache_type_k/v: 'q8_0', flash_attn_type: 'auto'})
        │                   8-bit KV cache is half of f16; a backend that rejects it
        │                   (quantised V needs flash attention) gets one retry on f16.
        │                   progress 0..1 drives the banner; GPU failure retries on CPU
        └─ ready            projector NOT attached yet: status.visionAvailable only
```

Failures are classified once (`classifyLoadFailure` in `errors.ts`): a missing
native library is "engine unavailable", allocation failures are "not enough
memory" with quantisation and context advice, header failures are "corrupt".

### 3.3 Send path (`state/chat.ts`)

```
send(text, image?)
  1. first message? create the conversation, titled from the text
  2. ensureModelLoaded()  BEFORE any write: a load failure is stored as an
                          error turn, never as a question with no answer
  3. persist the user turn (estimated token count)
  4. buildPrompt()        core/prompt.ts, see 3.4. If it carries an image and the
                          projector is not attached: check MemAvailable against the
                          projector alone (the model is already resident), then
                          engine.ensureVision() -> initMultimodal() on the live
                          context. Either failing is stored as an error turn. A
                          failed attach is remembered until the next load.
  5. insert an empty assistant row, then engine.generate():
       tokens -> in-memory buffer -> UI at ~30 fps (33 ms timer)
                               -> SQLite at most every 2 s (silent write)
  6. finalise: tokenizer count replaces the estimate; context-full is noted
```

Edit-and-resend and regenerate delete from the edited/last turn onward and
re-enter at step 2.

### 3.4 Prompt construction (`core/prompt.ts`)

- Newest turns backwards until 70% of the window, at most 40 messages; the
  latest turn is always kept.
- Error turns and empty placeholders are never sent back to the model.
- Past `<think>` reasoning is stripped from assistant turns before resending.
- Only the newest image is attached, and only when a projector is available.
- System prompt precedence: chat persona, else the user's default instruction,
  else the built-in study prompt, plus an "offline, use LaTeX" suffix. Never
  stacked.
- Repeat penalty comes from the model card when it specifies one.

---

## 4. Data

One file, `library_ai.sqlite`, opened with `PRAGMA journal_mode = WAL` and
`foreign_keys = ON`. Migrations are an append-only array in
`core/db/schema.ts`, tracked with `PRAGMA user_version`. Timestamps are epoch
milliseconds.

| Table | Purpose |
|---|---|
| `personas` | Six seeded study personas (`is_built_in`) plus the user's own |
| `conversations` | Thread; `model_id` is a catalogue id (survives model deletion); `persona_id`, `context_length_override`, **`pinned`** (new) |
| `messages` | Turn; `image_path`, `is_error`, `render_math`, `token_count` + `is_estimated_tokens`; v2 adds `prompt_tokens`, `tokens_per_second`, `generation_ms` for the per-reply readout |
| `model_installations` | One per model: quant, paths, verified `sha256`, `repo_sha` baseline |
| `model_update_checks` | Last check time and the display-only `update_available` flag |
| `setting_entries` | Key/value preferences; keys match the Flutter build |
| `documents`, `document_chunks` | Phase 2 (RAG) placeholders, unchanged |

**Reactivity.** Every write calls `emitChange(table)` (`core/db/events.ts`),
coalesced per microtask. Stores subscribe with `onChange([...])` and re-query.
Streaming flushes pass `{ silent: true }` because the screen already shows the
live text.

**Upgrading from the Flutter app (`core/services/legacyImport.ts`).** The RN app
keeps the Flutter application id `com.libraryai.library_ai`. Installed over the
old app (signed with the same key), it finds the drift database at
`<data>/app_flutter/library_ai.sqlite` and imports custom personas,
conversations, messages, settings, and installations whose files still exist.
Models already live in `<data>/files/models/<id>/`, which is where this build
looks, so nothing is downloaded twice. It runs once (`legacy_import_done`), and
a failure is retried on the next launch instead of blocking startup.

---

## 5. Rendering a message

`core/utils/markdownBlocks.ts` splits a reply into blocks in pure TypeScript:

```
raw reply
  ├─ <think>…</think>   -> ThinkBlock   collapsed, "Reasoned for N words", shimmer while open
  ├─ fenced code        -> CodeBlock    Prism tokens, warm theme, copy, horizontal scroll
  ├─ display maths      -> MathBlock    KaTeX HTML + bundled fonts in a self-sizing WebView
  └─ everything else    -> Markdown     marked lexer -> native Text, inline $…$ as Unicode
```

The splitter rules are the Flutter ones, ported with their tests: code is never
maths; inline `$` needs non-space ends on one line (so "$5 and $10" stays
prose); `\$` is literal; "Render maths" (per message) wraps bare `\commands`
only when the name is in the 207-command vocabulary.

Decisions specific to React Native:

- **Inline maths is Unicode, not TeX.** React Native has no inline TeX engine
  and a WebView per `$x$` would wreck scrolling, so `latexToPlainText` renders
  `x²`, `∑ᵢ₌₁ⁿ`, `ℝ`, `E⃗`, `√(x)`, `(a)/(b)` in the serif italic, using every
  Unicode super/subscript, double-struck letter and combining accent there is.
  Display maths gets real typesetting.
- **Display maths is KaTeX with its own fonts.** KaTeX runs in Hermes and emits
  HTML (plus hidden MathML for screen readers). Its 20 fonts are inlined into
  one stylesheet, `katexCss.generated.ts`, produced by
  `scripts/build-katex-css.mjs` (rerun it after upgrading katex). On Android
  the stylesheet is written once to the cache directory and linked from each
  formula's WebView, so formulas look identical on every device, delimiters
  stretch, and nothing is fetched. An earlier MathML-only version relied on the
  device having a math font and drew matrix brackets unstretched. The WebView
  refuses navigation and only posts its measured height. Broken TeX shows its
  source in a red-edged chip.
- **Streaming is smooth by construction.** An unterminated fence renders as an
  open code block; an unclosed `$$` is held back until it closes
  (`holdOpenDisplayMath`), so raw TeX never flashes on screen.

### Token and speed readout

Modelled on Claude Code's status line (`components/chat/TokenStats.tsx`):

```
✻ Writing… (4.2s · ↓ 312 tokens · 41.2 tok/s)      live, while a reply streams
↑ 1.2k · ↓ 312 tokens · 41.2 tok/s · 7.9s           saved under every reply
```

The spinner cycles Claude Code's glyphs (static under reduced motion); the verb
is "Reading prompt" before the first token, "Thinking" inside an open
`<think>`, then "Writing". ↑ is the prompt the model read (llama.cpp's
`tokens_evaluated`, estimated until it reports), ↓ the reply. Live tok/s is
decode speed measured from the first token (`core/streamStats.ts`), so prompt
processing does not drag it down; the saved figure is llama.cpp's own
`predicted_per_second` when available. Counts abbreviate like Claude Code
(`1.2k`).

PDF export (`core/services/exporter.ts`) builds HTML from the same blocks
(inline maths through placeholders so `marked` never sees TeX) and prints it
with `expo-print`, embedding the same KaTeX stylesheet. It is light-on-white
because it is read on paper.

---

## 6. Models: storage, downloads, updates

### 6.1 Storage

```
<files>/models/<modelId>/<file>.gguf        quantisation
<files>/models/<modelId>/mmproj-*.gguf      vision projector
<files>/models/<modelId>/<file>.part        in-progress download
<files>/attachments/<timestamp>.jpg         images copied out of the picker cache
<cache>/exports/*.pdf|*.md|*.json           handed to the share sheet
```

`<files>` is `Context.getFilesDir()`, the same directory the Flutter build used.

### 6.2 Downloads (`core/services/downloadManager.ts`)

Non-negotiables, all covered by `__tests__/downloadManager.test.ts`:

1. **Gates before bytes.** Offline, Wi-Fi-only on mobile data, and not enough
   free space (`df`, plus 500 MB headroom) all refuse before a request is made.
   Wi-Fi-only requests are also bound to Wi-Fi by the OS (`wifiOnly`), and the
   gate is re-checked before every file.
2. **Not a model until the checksum matches.** Bytes stream to `.part`; the
   SHA-256 is computed natively by streaming the file; a mismatch deletes the
   partial; a match renames into place; only then is the installation row
   written (which also clears the stale update flag).
3. **Resume, never restart silently.** Pause, network loss or app death keep
   the `.part`. Resume sends `Range: bytes=N-` in append mode. A `200` to a
   ranged request means the server ignored the range: the partial is discarded
   and one full request is made. Leftover partials are rebuilt as paused tasks
   at launch (`restorePartials`), so the Library offers Resume.

### 6.3 Notifications

Progress posts in place (one identifier per model) on a silent low-importance
channel, about once a second, with percentage, speed and ETA, plus a Pause
action. Completion and failure use a separate default-importance channel. The
permission is requested when the first download starts; declining costs only
the notification.

**Lost in the port:** the Flutter build ran a `dataSync` foreground service
with wake and Wi-Fi locks so Doze could not suspend a screen-off transfer, and
showed a determinate progress bar in the shade. `expo-notifications` offers
neither. Transfers continue while the process lives; if Android kills it, the
partial survives and Resume continues from the last byte. Restoring the
service needs a small local Expo module (Kotlin); see section 9.

### 6.4 Update checks (`core/services/updateChecker.ts`)

Once per launch after 5 s and when connectivity returns. Offline is a silent
skip; Wi-Fi-only models are never polled on mobile data; each model at most
once per 24 h. The per-file LFS oid (which *is* the SHA-256) is compared with
the installed checksum, with the repo commit as fallback. **A check can only
ever produce a badge**: the module holds no reference to the download manager,
and `offlineBoundary.test.ts` asserts it.

---

## 7. Interface and motion

The visual system comes from `../docs/CLAUDE_UI_INVENTORY.md`: warm ivory
canvas, near-black ink, a single clay accent, no shadows or gradients, Lora for
display, Lato for UI and body, JetBrains Mono for code. Dark mode is designed,
not inverted (warm charcoal, same hierarchy). Tokens live in `theme/tokens.ts`;
components read `useTheme().colors` and never hard-code hex values.

| Surface | Behaviour |
|---|---|
| Home | Serif greeting by time of day; four starters rise in on a 60 ms stagger and fill the composer rather than sending |
| Chat | User turns in a soft bubble; assistant turns have no bubble, with a breathing book mark in the gutter while writing. Action row: copy, regenerate, maths toggle, delete, token count. The list follows the stream only while you are at the bottom, with a jump-to-latest button |
| Composer | Floating pill; clay border is the focus indicator; send morphs to stop; attach is disabled with an explanation for text-only models |
| Sidebar | Edge-swipe or menu; 280 ms ease-out with the content pushed 22%; search over titles and message text; recency groups and pinned; swipe to delete with Undo; long-press for actions |
| Sheets | Model switcher, persona picker, chat actions (rename, pin, persona, duplicate, PDF, Markdown, delete); timed ease-out in, drag down to dismiss |
| Top bar | Model switcher title; a 2 dp context meter on its bottom edge that turns amber at 75% and red at 90%; long-press for numbers |

Motion rules: only transform and opacity animate; travel uses timed ease-out
(a spring across a full screen has a long tail); presses use springs; every
animation honours the system reduced-motion setting (`useReducedMotion`, and
Reanimated's default `ReduceMotion.System`). Shared values are written with
`.set()` to satisfy the React Compiler lint.

Accessibility: white on the light-mode clay accent is about 3.3:1, which fails
AA for text, so filled text buttons are ink-on-canvas and the accent is
reserved for icons and indicators. Everything tappable has a role and label;
the slider supports accessibility increment and decrement.

---

## 8. The offline guarantee

Chat, history, rendering, maths, code, export, personas, attachments and
settings never touch the network. Enforced by
`__tests__/offlineBoundary.test.ts`: any network API outside
`updateChecker.ts` (metadata), `files.native.ts` (model transfer) or
`connectivity.ts` (link state) fails the suite. The network is used to
download a model you chose and to check whether it changed. Nothing else.

---

## 9. Known gaps and limitations

1. **No foreground service for downloads** (section 6.3).
2. **No custom storage folder (SAF).** The Flutter build could keep models in a
   user-chosen folder and opened them as `/proc/self/fd/N`. llama.rn needs a
   real path, so models live in app storage. Legacy installs inside a SAF
   folder are skipped by the importer and show as "re-download".
3. **No model moving or adoption scan.** These were SAF features.
4. **Bundled catalogue is a copy.** `assets/models_catalogue.json` duplicates
   the root file; `catalogue.test.ts` fails if they differ. Copy it after
   running `tool/generate_models_catalogue.py`.
5. **Web build is a preview only.** In-memory database, a demo backend that
   streams a canned answer, no downloads. It exists to review the interface.
6. **Not yet run on a device.** Typecheck, lint, 131 unit tests, `expo-doctor`
   and a production Android bundle pass. The native build is exercised by the
   `apk` job in `.github/workflows/mobile-ci.yml` or `eas build`.
7. **Bundle size.** The Android Hermes bundle is about 12 MB, mostly KaTeX
   (including about 360 KB of inlined fonts), Prism and the Phosphor icon set.
   Deep icon imports would trim it.
