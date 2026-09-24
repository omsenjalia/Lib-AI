# Verification record

This file exists because of decision **D4**. The sandbox this project was built in
has no Flutter or Dart SDK, and `pub.dev` is not reachable from it. That means
`flutter pub get`, `flutter analyze`, `flutter test` and `flutter build apk`
**were never run here**. Everything below is what *was* run, what it proved, and
what is left to CI.

The rule this file follows: a claim is only ticked if a command produced evidence
for it. Nothing here is inferred from "the code looks right".

---

## 1. What was verified in the build environment

### 1.1 Download URLs and file sizes — against the live HuggingFace API

| Check | Method | Result |
|---|---|---|
| Every file size in the catalogue is the real byte count | `GET /api/models/{repo}/tree/main?recursive=true` for all 6 GGUF repos, compared file-by-file against `tool/generate_models_catalogue.py` | 94/94 quants + 4/4 mmproj files match exactly |
| Every model id / repo id exists | Same API call; `id`, `sha`, `lastModified` read per repo. The Phi-4 id in the brief (`bartowski/Phi-4-mini-instruct-GGUF`) **404s**; the real repo is `bartowski/microsoft_Phi-4-mini-instruct-GGUF` (bartowski prefixes the upstream org with an underscore) | 6/6 resolved |
| `sha256` values are the real file checksums | `lfs.oid` from the tree API *is* the SHA-256 of an LFS file. For the five pre-Phi models, a blob page was fetched and the published digest compared against the recorded one; Phi-4-mini's 23 values were taken from that repo's tree API and compared against the generator | 5/5 blob-page matches on the original five · 23/23 tree matches for Phi-4-mini |
| `sizeGb` in the JSON agrees with `sizeBytes` | Recomputed in Python over the shipped asset (`abs(published - bytes/1e9) < 0.01`) | 94/94 agree |
| Download URL shape | Recomputed every `downloadUrl` in Python and checked it is `https://huggingface.co/{ggufRepoId}/resolve/main/{fileName}` | 98/98 well-formed |
| The 27B's smallest quant | Sorted the real quant list by size | `UD-IQ2_XXS` is the smallest; it is the recommended one |
| Vision claims | Cross-checked each model card + the presence of an `mmproj-*.gguf` in the repository it is downloaded from | 4 vision-capable with an mmproj in-repo, 2 text-only with no mmproj |

Three of the six models have **no GGUF in their official repository**:
`Qwen/Qwen3.8-27B` ships safetensors only; `XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B`
ships safetensors only and the `ggml-org` conversion offers only `Q8_0`, at 9.5 GB;
`microsoft/Phi-4-mini-instruct` ships safetensors only and names no GGUF repo on its
model card. All three therefore use a community GGUF, which is decision **D3**.

### 1.2 Workflow YAML

Every file in `.github/workflows/` was parsed with `yaml.safe_load`:

```
ci-test.yml           OK  on=['pull_request','push','workflow_dispatch']
ci-build-signed.yml   OK  on=['pull_request','push','workflow_dispatch']
nightly-release.yml   OK  on=['schedule','workflow_dispatch']
pr-check.yml          OK  on=['pull_request']
release.yml           OK  on=['push','workflow_dispatch']
```

`release.yml` additionally carries a `push: tags: ['v*']` filter, so it cannot
publish on an ordinary branch push. Each job's step count, `runs-on` and
`timeout-minutes` were read back out of the parsed structure to confirm the jobs
are the shape they claim to be.

### 1.3 Static validation of the Dart tree

With no SDK, the only compiler available is one written for the occasion. Four
passes were run over every `.dart` file in `lib/` and `test/` (51 + 8 files,
14,530 + 2,124 lines):

| Pass | What it does | Result |
|---|---|---|
| Structure | Tokenises strings (including raw and triple-quoted), string interpolation and comments, then checks every brace/paren/bracket is balanced | 0 files with problems |
| Imports | Resolves every relative and `package:library_ai/…` import to a real file, and checks at least one declared symbol from each import is referenced. (`dart:` and third-party imports are skipped: checking those needs a package symbol table) | 0 broken imports, 0 unreferenced project imports |
| Member access | Builds a class→members table by brace-depth parsing each class body, resolves supertypes transitively, infers the type of each local/parameter, then checks every `receiver.member` against it | 0 unresolved (11 candidates, all traced to `AsyncValue.when`, `String.length`, drift's inherited `transaction`, and similar) |
| Named arguments | Extracts the declared named parameters of every function/method/constructor and checks each call site's named arguments against the union of same-named declarations | 0 real mismatches (33 candidates, all `ThemeData.copyWith`, `MarkdownStyleSheet.copyWith`, Flutter's `Row`, the notification plugin's `show(id:, body:, notificationDetails:, payload:)`, and one function-typed parameter the extractor cannot see) |

These are *not* a substitute for `dart analyze`. They cannot see type errors,
null-safety violations, or missing `const`. They catch the class of mistake that
is most likely in a tree this size: a call to a member that does not exist, an
argument named something the callee never declared, and an import that does not
resolve.

The four checkers are throwaway scripts, not committed, so this table is a
record of a result rather than something CI can re-run. CI runs the real
analyzer.

**Behaviour, not just structure.** Three of the suites are pure string handling,
so a line-by-line Python port of `latex_splitter.dart` and `markdown_blocks.dart`
was used to execute their assertions - 53 checks covering the splitter (22), the
markdown block splitter (15) and the two rendering-pipeline scenarios that use
them (13). Result: **50 pass, 0 fail, 3 skipped**; the skips are the cases that
need `latexToPlainText`/`pdfSafeText` (unported) and Dart's `==` override. This is
a port and not the Dart code, so it is evidence about *logic*, never about types
or compilation - but it is what caught two real bugs in this round:

- `\nis` - prose, where a newline escape is followed by the word "is" - was
  detected as the command `nis` and rendered as a broken formula. The splitter now
  tests the name after the backslash against the converter's command vocabulary
  (207 names, `isKnownLatexCommand` in `latex_to_text.dart`) instead of a list of
  single-letter escapes, and treats an unknown name as prose.
- Adding that vocabulary immediately broke `\frac{a}{b}`, because `\frac` is
  rewritten positionally by the converter rather than mapped to a character and so
  was absent from its tables. The port suite failed on the first run; `frac`,
  `dfrac`, `tfrac`, `cfrac` and `binom` are now listed, and both the escape case
  and the fraction case are locked down in `test/utils/latex_splitter_test.dart`
  and `test/utils/latex_to_text_test.dart`.

**What the closing audit changed.** Reading the tree against the same figures this
document quotes turned up four things, all fixed:

- `ARCHITECTURE.md` said `go_router` was skipped because of "six screens"; there
  are five. The conclusion is unchanged, the count was not.
- `ci-build-signed.yml` was the only workflow with no `permissions:` block. It now
  states `contents: read`, so all five run with the least privilege they can.
- `ci-test.yml` checked that `lib/core/data/database.g.dart` was up to date by
  running `git diff` on it - a file that is not in the repository, so the step
  could only ever pass vacuously. It now fails when `build_runner` does not
  produce the file at all, which is what actually happens when the schema stops
  compiling, and `.gitignore` now ignores `*.g.dart` so the generated file shows
  up as generated rather than as an unexplained dirty file.
- The line counts above were wrong by exactly the file counts beside them
  (14,581 + 2,132 for 51 + 8 files). Both were re-measured on the committed tree
  and on the working tree, which agree; the totals are in the paragraph above.

Deliberate rather than missing, for anyone comparing this against `flutter
create`: there is no `.metadata` (nothing here relies on the migration
bookkeeping), no `CHANGELOG.md` and no `LICENSE` (README states the licence), no
`l10n.yaml` (English only), and no Gradle wrapper - `flutter build` regenerates
`gradlew`, `gradlew.bat` and `gradle-wrapper.jar` from its own template, which is
why `android/.gitignore` ignores them.

### 1.4 The catalogue and generator

`tool/generate_models_catalogue.py` is the only writer of
`assets/models_catalogue.json`. It was regenerated and the output re-verified
after every edit:

- 6 models, 94 quantisations, 65,408 bytes.
- Every entry has a 64-hex `sha256`; every `fileName` ends in `.gguf`.
- The 27B is the only entry with `wifiOnly: true`, the only one with
  `highRam: true`, and the only one where every quant has
  `fitsTargetDevice: false`. Phi-4-mini is the mirror image: the only model
  where every quant has `fitsTargetDevice: true`.
- `microsoft/Phi-4-mini-instruct` is recorded as text-only on the evidence of
  its own metadata: `pipeline_tag=text-generation`, no vision or multimodal
  tag, no `preprocessor_config.json`, and no `mmproj-*.gguf` in the GGUF repo.
- `assets/models_catalogue.json` is declared in `pubspec.yaml` under
  `flutter: assets:`.

### 1.5 The decision tree for the inference framework

The brief's Phase 2 tree required three yes/no answers before committing to
Flutter. They were answered from the binding's source, README and issue tracker,
not from memory:

| Question | Answer | Evidence |
|---|---|---|
| Can it load a GGUF on Android? | **Yes** | `fllama` ships an Android plugin project and a Codemagic workflow that builds and runs it on a device; `OpenAiRequest.modelPath` takes a filesystem path. |
| Does it support image + text input? | **Yes** | `OpenAiRequest.mmprojPath`, and a README example that runs `Qwen2-VL-2B-Instruct` with a projector. |
| Is token streaming exposed as a callback? | **Yes** | `fllamaChat(request, (response, done) { … })`. |

All three are yes, so the tree's first branch applies and the app is Flutter +
`fllama`. No fallback branch was needed.

One caveat that the tree did not anticipate, and which the code works around:
the streaming callback delivers **cumulative** text, not deltas (fllama's own
example app diffs it). `InferenceEngine` converts it to deltas before handing
text to the UI.

### 1.6 The fllama API this app is written against

The dependency is pinned to `Telosnex/fllama@f624e4bfaf6c354d557ddc841ae4990760819c4a`
because the package published to pub.dev under the name `fllama` is an unrelated
fork. The API surface used by `lib/core/services/inference_engine.dart` was read
out of that commit:

- `fllamaChat`, `fllamaInference`, `fllamaCancelInference`, `fllamaTokenize`,
  `fllamaChatTemplateGet`, `fllamaEosTokenGet`, `fllamaBosTokenGet`,
  `fllamaGpuMemoryInfoGetAll`, `fllamaOutputIndicatesLoadError`.
- `OpenAiRequest` exposes `temperature`, `topP`, `frequencyPenalty`,
  `presencePenalty`, `maxTokens`, `modelPath`, `mmprojPath`, `numGpuLayers`,
  `contextSize`, `nParallel`, `jinjaTemplate`, `enableThinking`.
- There is **no load/unload call**, so the 1-token warm-up is used to force the
  weights resident, and `estimatedReleaseAt` is derived from the binding's own
  120 s inactivity sweep with margin.

**It does not expose `topK`.** That is decision **D2**, and the reason the
Settings screen labels the top-k slider as not applied by the current engine.

### 1.7 The download-notification layer

`flutter_local_notifications` was chosen over a foreground service: one
notification updated in place, versus a second process, a second download manager
and a wakelock. Its API was read from pub.dev rather than assumed, because the
whole feature is one plugin call away from a compile error:

- **Version ceiling.** 22.3.1 is the newest release that resolves here: it
  declares `sdk: ^3.10.0` and `flutter: >=3.38.1`, both satisfied, where master is
  an unreleased `23.0.0-dev.1` requiring Dart `^3.12.0` and Flutter >= 3.44.0. The
  pin is `^22.3.1`, and `environment.flutter` was raised from 3.38.0 to 3.38.1 to
  meet the plugin's own floor.
- **Named parameters, not positional.** `initialize({required settings, ...})`,
  `show({required int id, String? title, String? body, NotificationDetails?
  notificationDetails, String? payload})`, `cancel({required int id, String? tag})`.
- **Enumerations.** `Importance.low`, `Priority.low` and
  `AndroidNotificationCategory.progress` / `.error` are all real members of the
  version pinned.
- **Launch and action plumbing.** `NotificationAppLaunchDetails
  .didNotificationLaunchApp` and `.notificationResponse`; on `NotificationResponse`
  the fields used are `id`, `actionId` and `payload` (`NotificationResponseType`
  exists, but the service keys off `actionId`, which is what the manifest receiver
  delivers). The manifest declares
  `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` with
  `android:exported="false"`, and `POST_NOTIFICATIONS` is requested at the moment a
  download starts.
- **Small icon.** `ic_stat_download.xml` is a `drawable` (Android requires a
  drawable, not a `mipmap`, for status-bar icons), white on transparent so the
  system can tint it.

The mapping from `DownloadTask` to on-screen content is a pure function, so it is
unit tested without a platform channel
(`test/services/download_notification_service_test.dart`), including the FNV-1a
notification id, which is asserted against hard-coded values: the ids have to be
stable across processes, or a relaunched app cannot cancel what a killed one left
in the shade.

The manifest and the drawable were re-parsed with `xml.dom.minidom` after editing,
and the new file passes the same structure, import and member passes as the rest of
the tree.

**Not verified:** that the plugin compiles against this code, that the permission
prompt appears, or that Android renders any of it. All three need a device.

---

## 2. What is verified by CI instead

These are the Phase 7 items that need a runtime. They are wired as CI steps and
will be answered by the first push, not by this document:

| Item | Where it is checked |
|---|---|
| The project compiles · `flutter analyze` is clean | `ci-test.yml`, `pr-check.yml` |
| `drift` codegen (`lib/core/data/database.g.dart`) succeeds | every workflow, before analyze/test/build |
| `flutter test` passes, including the database, catalogue and rendering suites | `ci-test.yml`, `release.yml` |
| A signed (or debug-fallback) `release.apk` builds | `ci-build-signed.yml`, `release.yml`, `nightly-release.yml` |
| The APK installs and a model loads | manual, on the target device — no CI can do this |
| PDF export produces a valid file | manual + the offline pipeline test in `test/ai_eval/` |

The CI test job is deliberately `continue-on-error` with a separate failing
step, so a red run still posts its output as a PR comment instead of leaving
nothing to look at.

---

## 3. Honest summary

**Verified here:** every byte count, every checksum's provenance, every download
URL, the YAML of all five workflows, the structural integrity of all 59 Dart
files, the absence of unresolved imports and unknown members, the catalogue's
internal consistency, the scripted behaviour of the two pure-Dart splitters, and
the three framework-capability questions.

**Not verified here:** that the code compiles, that it analyzes clean, that any
test passes, that the APK builds, and anything at all about behaviour on a
device.

Those are stated as unverified in `README.md` and here, rather than assumed.
