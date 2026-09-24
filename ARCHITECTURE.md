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
| **flutter_local_notifications + a small Android foreground service** | A user-started multi-gigabyte transfer needs both an in-place notification and an OS-visible `dataSync` lifetime while the screen is off. The service does not own HTTP or create a second `DownloadManager`; Flutter continues to own the transfer, and the plugin updates the service notification by stable id. |
| **saf (Android Storage Access Framework)** | Optional, user-selected model storage through `ACTION_OPEN_DOCUMENT_TREE` with a persisted read/write grant. It avoids broad storage permissions; app-private model storage remains the default and the fallback if access is revoked. |

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
lib/core/services/            inference, downloads, SAF storage/adoption/migration, notifications, updates, export
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
  │    ├─ installation record -> app path or SAF content URI  (SQLite)
  │    ├─ StoragePaths opens a SAF fd as /proc/self/fd/<n>     (if needed)
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
| `n_gpu_layers` | Requested layers are used only when `fllamaGpuMemoryInfoGetAll()` reports a real GPU backend. The pinned Android CMake build enables neither OpenCL nor Vulkan, so the Galaxy S25 currently runs CPU-only; the engine forces zero GPU layers and retries CPU if a GPU warm-up fails. |

The pinned `Telosnex/fllama` source enables Vulkan only on Windows and Metal on
Apple platforms. Its Android CMake branch contains ARM CPU optimizations but
does not enable an Android GPU backend. The Settings screen probes the native
GPU enumerator and hides the layer slider when no device is reported. The S25's
Adreno GPU therefore is **not accelerated by this build**; no performance claim
is made. A future Android build must actually compile and package a supported
backend (for example, Vulkan/OpenCL) before the control can appear. The separate
`llama_cpp_dart` project ships OpenCL and Hexagon NPU artifacts, but switching
engines is a native dependency decision and has not been done here.

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
| `subject_tags` | Retired legacy table | Kept for Drift schema compatibility only; v2 clears its rows and the app no longer reads or writes tags |
| `personas` | Six seeded study personas plus custom ones | `systemPrompt` is sent before every turn |
| `conversations` | One chat thread | Legacy `subjectTagId` is cleared by v2 and no longer used; `personaId` is nullable; `modelId` is a catalogue string, **not** a row id, so a thread survives its model being deleted; `contextLengthOverride` allows per-thread context |
| `messages` | One turn | `role` is text; `imagePath` points at an app-private attachment copy; `isError` distinguishes a stored failure from something the model said; `renderMath` is the per-message toggle; `tokenCount` + `isEstimatedTokens` keep the meter honest |
| `model_installations` | Downloaded or re-adopted models, **keyed by `modelId`** | One active quantisation per model: switching quant means downloading again. Holds `localPath` and `mmprojPath` as app paths or SAF content URIs, the verified `sha256`, and the `repoSha` / `repoLastModified` baseline the update checker compares against |
| `model_update_checks` | Throttle and result of the last check | `lastCheckedAt` enforces once-per-24h; `updateAvailable` is display-only and never triggers a download |
| `setting_entries` | Key/value preferences | `SettingKeys` constants; unparseable values fall back to defaults so a corrupt preference cannot stop startup |
| `documents` | **Phase 2 placeholder** | `pageCount`, `chunkCount`, `embeddingModelId` |
| `document_chunks` | **Phase 2 placeholder** | `chunkIndex`, `content`, `tokenCount`, `embedding` as a float32 blob |

Schema version is 2. Version 2 clears legacy conversation tag assignments, the
old tag rows, and the stored default-tag preference; it retains those old SQL
columns/tables solely to keep the checked-in generated Drift schema compatible.
The selected model-tree URI and display name are ordinary `setting_entries`
keys, so SAF does not require another schema migration. Generated Drift code
(`database.g.dart`) is not hand-edited; CI runs
`build_runner` before compiling.

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
<app support>/                    default and grant-revocation fallback
  models/<modelId>/<file>.gguf    the quantisation
  models/<modelId>/mmproj-*.gguf  the vision projector, when there is one
  attachments/<timestamp>.jpg     images attached to a turn

<user-selected SAF tree>/         optional; persisted ACTION_OPEN_DOCUMENT_TREE grant
  models/<modelId>/<file>.gguf    same managed layout, reached as content URIs

<app external files>/LibraryAI/   Android/data/<package>/files/LibraryAI
  exports/*.pdf, *.zip            reachable from a file manager or over USB
```

App-support is the default for multi-gigabyte model data. The user may opt into a
folder through Android's Storage Access Framework; the app holds only a
persisted read/write grant to that selected tree, and its own files are kept in a
`models/` subdirectory. If the grant is missing or the document provider becomes
unavailable, new operations safely fall back to app-private storage and the chat
screen shows one dismissible in-app banner with the reason. Choosing the folder
again re-establishes the grant and triggers a local scan for known model names;
each candidate is streaming-hash-verified against the bundled catalogue before
its installation row is adopted, so a reinstall can reuse files without
re-downloading them. Files in the user-selected tree remain on-device after
uninstall, but Android removes the app's permission and the user must select the
folder again after reinstall. App-private model files do not survive uninstall;
Settings reports remaining private model bytes through `hasFragileUserData` and
warns that they must be moved before uninstall if they need to be kept.

`ModelInstallation.localPath` remains a string for compatibility, but may be a
normal app path or a SAF `content://` URI. `StoragePaths` opens SAF model files
through a retained native descriptor and gives fllama its `/proc/self/fd/<n>`
path for the duration of the loaded model. Moving models is a per-model,
resumable operation: it streams to `.move.part`, verifies the destination,
updates the installation row, and only then removes the old copy. Pending model
ids are stored in `setting_entries`; an interrupted move can be resumed from
Settings. Attachments are **copied** out of the camera app's cache, which the
system may clear at any time, into app storage, so a message is never left
pointing at a file that no longer exists. Exports go to the external files
directory so they can actually be opened, with a fallback to documents where
that is unavailable.

No broad storage permission is declared. The system document picker grants
access only to the folder the user selected; all other files remain app-scoped.

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
Network failures, a two-minute inactivity timeout, and the Pause action leave the
flushed `.part` file in place. On the next explicit retry the manager sends
`Range: bytes=N-`, requires a matching `206 Content-Range` and catalogue file
length, hashes the saved prefix together with new bytes, and checks the complete
catalogue SHA-256 before promotion. If the server ignores ranges, returns a
stale range, or the resumed digest is wrong, the partial is discarded and one
fresh full request is attempted. App launch never deletes download parts; the
Settings cleanup action explicitly discards them. `.move.part` files remain
preserved while their pending model id exists; pressing Resume re-streams and
re-verifies a storage migration before switching its installation row.

### 6.3 The download notification

A model is up to 7.3 GB, so progress cannot live only in a screen the user has to
hold open. `DownloadNotificationService` mirrors the shape Android users already
know from the Play Store:

```
phase          what is shown                                  actions
─────────────  ─────────────────────────────────────────────  ─────────────
downloading    "42% · 1.05 GB of 2.49 GB · 12.3 MB/s · 3m      Pause
               20s left", determinate bar, in place
verifying      "Verifying <model>", indeterminate bar          Pause
complete       "<model> is ready · Tap to open the Model       tap → library
               Library", dismissible
failed         "<model> could not be downloaded · <reason>"
cancelled      removed
```

The progress channel is **default importance, silent, and vibration-free**. That
keeps it visible in the shade without buzzing on every update. Completion and
failure use a separate **high-importance** channel, and each terminal state is
posted only once. Separate channel ids are intentional: Android remembers the
importance chosen when a channel is first created, so reusing the old low-
importance id would preserve the symptom this change fixes.

A user-started transfer also starts the app-owned Android `dataSync` foreground
service. It begins only when the first file is actively downloading or being
verified, and stops when the active-task map becomes empty. The service takes a
partial wake lock and Wi-Fi lock for that interval so Doze does not suspend a
large transfer when the screen turns off. It does not own the Dio stream or
restart work after process death; partial bytes survive for the next user retry.
The service's initial notification uses the same stable id and progress channel
as the first active model, then `flutter_local_notifications` replaces it with
the complete per-model text and Pause action. The manifest declares the
`FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` and lock permissions only
for this user-initiated transfer path; no storage permission is added. This is
the Play-policy user-initiated data-transfer case, not background polling.

Other design points:

- **One notification per model**, keyed by a stable FNV-1a hash. `String.hashCode`
  is not stable across processes, and the id has to survive a restart so the app
  can cancel what a killed run left in the shade.
- **The permission is requested when a download starts**, after the confirmation
  dialog. The result is checked with Android's notification-enabled state. A
  refusal never stops the download; Model Library shows a one-line hint instead.
- **Errors stay non-fatal but visible.** The Settings diagnostics row shows
  `_ready`, the last permission result, the last apply kind/percent/time and the
  last notification error. `show()` errors are logged in release builds too;
  collect them with `adb logcat -s flutter LibraryAI.DownloadService`.
- **Cancel brings the app forward.** The notification action is handled on the
  main isolate, where `DownloadManager` lives. `cancelNotification: false`
  leaves removal to the manager's terminal state, so a cancel racing with
  completion still shows the truth.
- **The notification layer never navigates.** It raises
  `openModelLibraryRequestProvider` and the app root pushes the route. That keeps
  `core/` independent of feature screens.

The mapping from `DownloadTask` to on-screen content is a pure function
(`downloadNotificationFor`), with its progress/terminal channel, importance and
priority policy unit-tested without a platform channel. The foreground-service
calls sit behind `ForegroundDownloadBridge`, so those tests remain platform-free.

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

1. **Top-k is not applied.** The pinned Android build has no GPU backend, so
   runtime capability detection keeps inference on CPU. If a future native build
   ships a supported GPU backend but warm-up fails, the engine retries on CPU.
   See 3.3.
2. **`unload()` is not immediate**, because fllama has no unload call. The model
   switcher says so, and switching models briefly holds two contexts.
3. **Free disk space is not pre-checked** before a download. Dart's `dart:io` has
   no `statvfs`, so the confirmation dialog reports the size and what models
   already occupy instead of a free-space figure. Running out of space fails
   cleanly and leaves any flushed partial bytes for a validated retry.
4. **The bulk export is a ZIP, and a ZIP cannot go through the system share
   sheet** from this app's printing integration. It is written to the exports
   directory (whose path is shown) and individual conversations can be shared as
   real PDFs from the chat menu.
5. **The 27B is unusable on this device.** It is catalogued, blocked on mobile
   data, and labelled. That is a deliberate choice, not an oversight.
