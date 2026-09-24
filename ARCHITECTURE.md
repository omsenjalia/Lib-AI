# Architecture

How Library AI is put together, and why. The short version: one SQLite file, one
resident model, one isolate doing the heavy work, and no code outside the model
layer that knows the internet exists.

---

## 1. Why these frameworks

| Choice | Why this, and what it rules out |
|---|---|
| **Flutter 3.44** | A single codebase with a real rasteriser. The alternative (native Kotlin) would have meant writing the markdown, TeX and PDF pipelines by hand; Kotlin's Markdown/KaTeX-equivalent story is much weaker. Flutter also gives the same CMake/NDK story the inference engine needs. |
| **Riverpod 2** | The provider graph is the app's dependency injection. It lets the settings controller be the single source of truth for preferences while services stay plain Dart classes that a test can construct directly. `ProviderScope` overrides are how a test swaps in an in-memory database. |
| **drift (SQLite)** | The schema is the app. Type-safe queries catch column typos at compile time; migrations are explicit; `NativeDatabase.createInBackground` keeps database I/O off the UI isolate for free. A document store would have been less code, but RAG's chunk/embedding relations are exactly what a relational schema is good at. |
| **fllama (pinned git ref)** | The only maintained llama.cpp binding with a multimodal (`mmprojPath`) API and streaming callbacks. It is not on pub.dev — the pub.dev package with that name is an unrelated fork — so it is pinned by commit. See the disclaimer in `pubspec.yaml`. Chapter 3 covers its lifecycle in detail. |
| **flutter_markdown + flutter_highlight** | Markdown is a solved problem; the code-block case is not, which is why highlighting is a separate renderer fed by a block splitter (`lib/core/utils/markdown_blocks.dart`) rather than a markdown plugin. `flutter_markdown` was chosen because the brief specifies it; it has since been discontinued upstream in favour of `flutter_markdown_plus`, which is API-compatible — that swap is a one-line change if it ever becomes necessary. |
| **flutter_math_fork + pdf** | TeX rendering that runs offline in pure Dart, and a PDF writer whose built-in fonts need no download. Chapter 5 explains the font constraint this creates. |
| **flutter_local_notifications** | Progress for a multi-gigabyte download has to survive the user leaving the app. The alternative — a foreground service — would mean a second process, a second `DownloadManager`, and a wakelock; a notification updated in place gets the same result for a fraction of the risk. It is the only dependency added purely for download UX. |

Deliberately **not** used: `go_router` (five screens, `Navigator` is enough),
`flutter_dotenv` (no backend, no secrets), `share_plus` (the PDF export shares
through the printing plugin, so a second sharing library would be redundant).

---

## 2. Layering

```
lib/main.dart                 ProviderScope -> LibraryAiApp
lib/app.dart                  theme, bootstrap (notifications, sweep, hydrate, scheduler)
lib/features/<feature>/       screens and widgets; read services through providers
lib/core/providers/           the graph: services, plus the app-wide ChatController
lib/core/services/            inference, downloads, notifications, updates, export
lib/core/data/                drift tables, AppDatabase, DAOs
lib/core/models/              immutable value objects (catalogue, settings, transfer)
lib/core/utils/               pure Dart: LaTeX, markdown blocks, PDF text, formatting
lib/core/widgets/             shared presentation with no feature knowledge
```

Three rules hold this together:

1. **Dependencies point downwards only.** A widget never talks to `dio`, and a
   service never imports a widget.
2. **`lib/core/utils/` is Flutter-free** wherever possible. `latex_splitter`,
   `latex_to_text`, `pdf_text`, `markdown_blocks`, `formatters` and
   `token_estimator` are plain Dart, so the trickiest logic in the app is unit
   testable without a device.
3. **Errors are values with advice.** `AppException` subtypes carry a `message`,
   an optional technical `detail`, and a `recovery` string that says what to do
   about it. Out-of-memory advice is specific ("choose a smaller quantisation or
   lower the context length"), because that is the failure this device will
   actually hit.

---

## 3. Inference pipeline

### 3.1 The constraint that shapes everything

fllama exposes **no load call and no unload call**. Weights are instantiated
lazily inside the first inference, and the native side caches one llama.cpp
context per model path in a `ServerManager`, reusing it only when the parameters
match (`n_ctx`, `n_gpu_layers`, and so on) and reaping it after 120 seconds of
inactivity, checked every 30 seconds.

Two consequences the app does not hide:

- **The first turn forces a 1-token warm-up.** Because there is no load call,
  the only way to discover that a model does not fit *before* the user asks a
  question is to run one token through it and watch for a failure. That is what
  `InferenceEngine._warmUp` does, and it is why the app can say "out of memory"
  while the composer says "Loading weights into memory" instead of silently
  producing a broken answer.
- **`unload()` does not free memory immediately.** It stops generation and marks
  the engine unloaded so nothing new is dispatched; the platform's own timer does
  the releasing. `estimatedReleaseAt` (last activity + 150 s) is surfaced so the
  model switcher can be specific about when switching is safe again.

### 3.2 Request path

```
ChatController.send()
  ├─ resolve or create the conversation row (title from the first message)
  ├─ ensureModelLoaded()
  │    ├─ installation record -> local paths                  (SQLite)
  │    ├─ catalogue entry -> QuantOption, context ceiling     (bundled asset)
  │    └─ InferenceEngine.load()
  │         ├─ verifying      file exists and is not truncated
  │         ├─ readingMetadata  fllamaChatTemplateGet, so a corrupt
  │         │                   header fails cheaply
  │         ├─ loadingWeights   1-token warm-up: commits memory and
  │         │                   surfaces OOM before the user waits
  │         └─ ready
  ├─ persist the user's turn (with an estimated token count)
  ├─ build the prompt (see 3.3) and insert an empty assistant row
  ├─ InferenceEngine.generate()
  │    ├─ fllamaChat(OpenAiRequest, callback)                 (helper isolate)
  │    ├─ callback text is CUMULATIVE -> diffed into deltas    (UI animation)
  │    ├─ streamed text flushed to SQLite at most every 2 s
  │    └─ tokeniser count on completion -> exact meter
  └─ assistant row finalised; conversation touched for sidebar ordering
```

Generation runs on fllama's own helper isolate, so the UI thread never blocks on
tokens. Nothing in this path is aware of the network.

### 3.3 Prompt construction

The prompt is assembled from the newest turns backwards, stopping at 70% of the
context window:

- Recent turns are kept and older ones dropped, because a question refers to the
  answer immediately before it.
- Error turns and empty placeholders are never sent back to the model.
- At most 40 messages are included.
- The persona's system prompt is prepended, always with a short suffix that
  states the user is offline and asks for LaTeX between `$...$`.

Sampling comes from settings, except the repeat penalty, which prefers the model
card's own recommendation (Qwythos and Mythos want 1.05; applying 1.1 everywhere
would be a guess).

**Two parameters are honest gaps, not bugs:**

| Setting | Status |
|---|---|
| `top_k` | Persisted and displayed, **not applied**. fllama's `OpenAiRequest` has no top-k field. The Settings screen says so in-line. |
| `n_gpu_layers` | Passed through to llama.cpp; the bundled native build targets CPU inference, so it currently has no effect. Labelled as such under Advanced. |

The Phase 2 upgrade path is `llama_cpp_dart`, which ships an arm64-v8a AAR with
OpenCL and Hexagon NPU backends, `MultimodalParams(mmprojPath:)`, token streaming
and session save/load. Swapping engines would both apply top-k and turn the GPU
layer slider into a real control. It is not used in v1 because it is a much
larger native dependency than the current one.

### 3.4 Failure handling

| Failure | What the user sees |
|---|---|
| File missing or too small to be real | "The model file is missing" plus "re-download it from Model Library" |
| GGUF header will not parse | "The model file could not be read" plus "the file may be truncated — delete and download again" |
| Out of memory during warm-up | "Not enough memory to load…" plus "choose a smaller quantisation (Q3_K_M or Q4_K_M), or lower the context length", with buttons that go to the Model Library and Settings |
| Model file deleted after install | The chat screen's model button turns red and reads "Missing model"; the error card offers a re-download |
| No model installed at all | An empty state with one action, plus a composer that explains why it is disabled |

Every one of these is persisted into the transcript as an error turn, so a
failure survives an app restart rather than vanishing.

---

## 4. SQLite schema

One file, `library_ai.sqlite`, in the app documents directory. Foreign keys are
enabled per connection (`PRAGMA foreign_keys = ON`) but deletions are still
explicit, so behaviour does not silently depend on that pragma.

| Table | Purpose | Notes |
|---|---|---|
| `subject_tags` | Nine seeded subjects plus custom ones | `colorValue` is an ARGB int; `isBuiltIn` only prevents deletion |
| `personas` | Six seeded study personas plus custom ones | `systemPrompt` is sent before every turn |
| `conversations` | One chat thread | `subjectTagId` and `personaId` are nullable FKs; `modelId` is a catalogue string, **not** a row id, so a thread survives its model being deleted; `contextLengthOverride` allows per-thread context |
| `messages` | One turn | `role` is text; `imagePath` points at an app-private attachment copy; `isError` distinguishes a stored failure from something the model said; `renderMath` is the per-message toggle; `tokenCount` + `isEstimatedTokens` keep the meter honest |
| `model_installations` | Downloaded models, **keyed by `modelId`** | One active quantisation per model: switching quant means downloading again. Holds `localPath`, `mmprojPath`, the verified `sha256`, and the `repoSha` / `repoLastModified` baseline the update checker compares against |
| `model_update_checks` | Throttle and result of the last check | `lastCheckedAt` enforces once-per-24h; `updateAvailable` is display-only and never triggers a download |
| `setting_entries` | Key/value preferences | `SettingKeys` constants; unparseable values fall back to defaults so a corrupt preference cannot stop startup |
| `documents` | **Phase 2 placeholder** | `pageCount`, `chunkCount`, `embeddingModelId` |
| `document_chunks` | **Phase 2 placeholder** | `chunkIndex`, `content`, `tokenCount`, `embedding` as a float32 blob |

Schema version is 1. Generated drift code (`database.g.dart`) is not committed;
CI runs `build_runner` before compiling.

---

## 5. Rendering: three engines, one message

A model answer can contain prose, code and mathematics, and each needs a
different renderer. `lib/core/utils/markdown_blocks.dart` does the split, in pure
Dart, so the rules are testable:

```
raw message
  ├─ fenced code          -> CodeBlock   -> flutter_highlight, with a copy button
  ├─ display maths        -> DisplayMath -> flutter_math_fork, centred and scrollable
  └─ everything else      -> ProseBlock  -> flutter_markdown, with inline $...$
                                            registered as a custom inline syntax
```

Design points that matter:

- **Inline maths stays inside the prose.** Lifting it out would break a sentence
  into three stacked widgets. The splitter therefore runs with
  `extractInline: false`, and the markdown layer renders `$x^2$` as an inline
  widget that flows with the text.
- **Inline maths is guarded by two rules.** The body must start and end with a
  non-space character and may not contain `$` or a newline. That is what stops
  "costs $5 and then $10" being typeset as an equation. An escaped `\$` is
  checked against the raw source, because markdown unescapes it later.
- **"Render math" exists for real models.** Some emit `\frac{a}{b}` with no
  delimiters at all; `splitLatex(forceMath: true)` wraps bare commands in `$...$`
  on the fly, and the toggle is per message and persisted.
- **A bare backslash is only maths if the name after it is a command.** The shape
  of the text cannot tell `\sin` from `\nis` - a newline escape followed by the
  word "is" - so the splitter checks the name against the same vocabulary the
  export converter uses (`isKnownLatexCommand`, 207 names). An unrecognised name
  is left as prose: raw LaTeX on screen is a smaller failure than a sentence with a
  broken formula inside it.
- **Broken TeX shows its source.** A formula that fails to parse renders the raw
  LaTeX in a red chip, because a model emitting broken TeX should look like that
  rather than like an app that lost the answer.

### PDF export and the font constraint

The `pdf` package's built-in fonts are WinAnsi-only: no Greek, no `√`, no `≤`, no
emoji. An offline app cannot fetch a Unicode TTF at export time, so the export
path transliterates instead (`pdfSafeText`): `α → alpha`, `√ → sqrt`, `x² → x^2`,
emoji dropped. Superscript and subscript digits are deliberately excluded from
the "already safe" set so a formula never mixes `x²` and `x^n` in one line.

LaTeX is converted to readable text for export (`latexToPlainText`):
`\frac{a}{b} → (a)/(b)`, `\sqrt{x} → √(x)`, `\binom{n}{k} → C(n, k)`. On-screen
rendering is unaffected and still uses the real TeX renderer.

The exported PDF is light-on-white even though the app is dark-mode-first: it is
read on paper and in other people's viewers.

---

## 6. Model management

### 6.1 Storage layout

```
<app support>/                    internal; never shown to the user
  models/<modelId>/<file>.gguf    the quantisation
  models/<modelId>/mmproj-*.gguf  the vision projector, when there is one
  attachments/<timestamp>.jpg     images attached to a turn

<app external files>/LibraryAI/   Android/data/<package>/files/LibraryAI
  exports/*.pdf, *.zip            reachable from a file manager or over USB
```

Models go in app-support storage: they are multi-gigabyte internal data that
should not appear in a file picker. Attachments are **copied** out of the camera
app's cache, which the system may clear at any time, into app storage, so a
message is never left pointing at a file that no longer exists. Exports go to the
external files directory so they can actually be opened, with a fallback to
documents where that is unavailable.

No storage permission is required anywhere: all of it is app-scoped.

### 6.2 Downloads

`DownloadManager` has one job and two non-negotiables:

1. **The Wi-Fi gate is re-checked before every file**, not once at the start, so
   dropping off Wi-Fi mid-download stops it. For a model flagged `wifiOnly` the
   block is absolute: mobile data is refused before a byte is requested. The
   Model Library screen surfaces this as a dialog explaining that the block is
   deliberate, not a setting.
2. **A download is not a model until its checksum matches.** Files stream to
   `<name>.part` while a SHA-256 is computed incrementally (`sha256` +
   a chunked sink, so a 7 GB file is never buffered in memory). On a mismatch the
   `.part` file is deleted and the model is not marked installed; on success it
   is renamed into place atomically, and only then is the installation record
   written and the update baseline reset.

Progress is reported per file, with file *n* of *m* when a projector is included,
because a second transfer starting from zero otherwise looks like a restart.
Interrupted `.part` files are swept on every launch.

### 6.3 The download notification

A model is up to 7.3 GB, so progress cannot live only in a screen the user has to
hold open. `DownloadNotificationService` mirrors the shape Android users already
know from the Play Store:

```
phase          what is shown                                  actions
─────────────  ─────────────────────────────────────────────  ─────────────
downloading    "42% · 1.05 GB of 2.49 GB · 12.3 MB/s · 3m      Cancel
               20s left", determinate bar, in place
verifying      "Verifying <model>", indeterminate bar          Cancel
complete       "<model> is ready · Tap to open the Model       tap → library
               Library", dismissible
failed         "<model> could not be downloaded · <reason>"
cancelled      removed
```

Design points that are deliberate rather than incidental:

- **One notification per model, updated in place**, keyed by a stable FNV-1a
  hash of the model id. `String.hashCode` is not stable across processes, and the
  id has to survive a restart so a relaunched app can cancel what a killed one
  left behind.
- **The channel is `Importance.low` with no sound.** A progress notification that
  buzzes every few seconds for twenty minutes is worse than none.
- **Nothing else in the app posts notifications**, which is what makes the
  `cancelAll()` at startup safe: it clears a progress bar that a killed process
  can never move again, because there is no background download service to
  resume it.
- **The permission is requested when a download starts**, after the confirmation
  dialog, and a refusal costs nothing but the notification.
- **Cancel is a notification action with `showsUserInterface: true`.** That
  brings the app forward so the request is handled on the main isolate, where the
  `DownloadManager` lives. `cancelNotification: false` leaves the removal to the
  manager's own terminal state, so a cancel racing with completion still shows
  the truth.
- **The notification layer never navigates.** It lives in `core/`, which must not
  import a feature screen; it raises `openModelLibraryRequestProvider` and the
  app root pushes the route. That is also why the whole feature is optional: if
  the plugin is unavailable or the permission is denied, every call is a no-op
  and the model card remains the source of truth.

The mapping from `DownloadTask` to on-screen content is a pure function
(`downloadNotificationFor`), unit-tested without a platform channel.

### 6.4 Auto-update, and the thing it must never do

```
connectivity regained ──► UpdateScheduler
once per launch (if online, after 5 s)
manual "Check now" ─────► UpdateChecker.checkAll(models)
                            ├─ offline?            -> silent no-op
                            ├─ checked < 24h ago?  -> skip (unless forced)
                            ├─ wifiOnly + mobile?  -> skip
                            ├─ GET api/models/{id}?blobs=true
                            ├─ per-file lfs.oid vs catalogue sha256,
                            │  repo sha as fallback
                            └─ store result -> badge + dismissible banner
```

**A check can only ever produce a badge.** `UpdateChecker` holds no reference to
`DownloadManager`, which is the structural guarantee that an available update
cannot start a transfer. Replacing a file requires the user to tap Update; the
new file downloads alongside the old one, is verified, and only then replaces it,
so a failed update leaves the working model untouched.

`lfs.oid` is used as the comparison key because it **is** the file's SHA-256: the
values in the catalogue were cross-checked against the checksums HuggingFace
publishes on its file pages.

---

## 7. RAG readiness (Phase 2)

Nothing in the inference pipeline knows about retrieval, and that is deliberate:
adding retrieval should be an addition, not a rewrite.

What is already in place:

- `documents` and `document_chunks` tables, with `embedding` as a float32 blob so
  the schema does not care about the embedding dimension, and
  `embeddingModelId` recorded now so a future re-embed can detect a model change.
- The **My Notes** screen, wired to a real document count, showing "Coming soon".
- The chat composer and prompt builder take a message list; retrieval would add
  context to that list rather than changing the engine's interface.

What is still needed:

1. A chunker (and a decision on chunk size, which the tokeniser can now answer).
2. An embedding model on device. This is why RAG is opt-in: it is another
   few hundred megabytes of storage, and the user should choose that.
3. Local similarity search. For a study-sized corpus this can be a linear scan in
   Dart over the blobs; an ANN index is not needed at this scale.
4. Attribution in the UI, so an answer that came from the user's own notes says
   which document it came from.

---

## 8. Performance notes

- **Cold start to chat-ready** is a database open, a settings read and one
  screen. No model is loaded at startup: loading gigabytes while somebody is
  merely looking at the app would slow the start and risk being killed for
  memory. The cost is that the first question waits for the load, which the UI
  shows as an explicit stage rather than a spinner.
- **Database I/O runs in a background isolate** (`NativeDatabase.createInBackground`).
- **The context meter is an estimate until it is not.** Character-ratio estimates
  drive it live while streaming; once a turn completes, the model's own tokeniser
  produces exact counts and the meter stops saying "estimated".
- **Streamed text is flushed to SQLite at most every two seconds.** Frequent
  enough that an app kill loses at most a couple of seconds of output, rare
  enough that a long answer is not hundreds of writes.

---

## 9. Known limitations

Stated here rather than discovered by a user:

1. **Top-k and GPU layers do not affect inference.** See 3.3.
2. **`unload()` is not immediate**, because fllama has no unload call. The model
   switcher says so, and switching models briefly holds two contexts.
3. **Free disk space is not pre-checked** before a download. Dart's `dart:io` has
   no `statvfs`, so the confirmation dialog reports the size and what models
   already occupy instead of a free-space figure. Running out of space during a
   transfer fails cleanly and the partial file is removed.
4. **The bulk export is a ZIP, and a ZIP cannot go through the system share
   sheet** from this app's printing integration. It is written to the exports
   directory (whose path is shown) and individual conversations can be shared as
   real PDFs from the chat menu.
5. **The 27B is unusable on this device.** It is catalogued, blocked on mobile
   data, and labelled. That is a deliberate choice, not an oversight.
