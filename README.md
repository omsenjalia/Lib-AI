# Library AI

**Learn anywhere. No internet required.**

An offline-first AI study assistant for Android. Runs open-weight language models
entirely on the phone: chat, conversation history, markdown and LaTeX rendering,
code highlighting, subject tagging, study personas and PDF export all work with
the radio off. The only thing the network is used for is downloading a model in
the first place, and checking whether one you already have has changed upstream.

Built for and tested against a Samsung Galaxy S25 (Android 15, Snapdragon 8
Elite, 8 GB/12 GB RAM).

---

## What it does

| Screen | What is there |
|---|---|
| **Chat** | Conversation sidebar (search, swipe-delete with undo, grouped by subject), Claude-style message layout, tappable model switcher, live context-window meter, subject and persona chips |
| **Model Library** | Five catalogued models, quantisation dropdown with real sizes and checksums, download progress with speed and ETA, update badges, per-model storage |
| **Study Personas** | Six built-in prompts (tutor, code reviewer, maths tutor, exam coach, paper explainer, essay editor) plus your own |
| **Settings** | Theme, default model and subject, context-length slider, sampling parameters, per-model storage, ZIP export, update policy |
| **My Notes** | Placeholder. Import and retrieval are Phase 2; the schema is already in place. |

Study features: markdown rendering, syntax-highlighted code blocks with a copy
button, inline `$...$` and display `$$...$$` LaTeX, a per-message "Render math"
toggle for models that emit bare LaTeX, OCR mode (camera → multimodal image
input, refused for text-only models), PDF export, and nine subject tags.

---

## Requirements

- Flutter **3.44.0** (stable) with Dart 3.10 or newer
- Android SDK with **NDK 28.2.13676358** and CMake (the inference engine
  compiles llama.cpp from source)
- An Android device or emulator, **arm64-v8a**

There is no backend, no account and no API key.

---

## Setup

```bash
git clone https://github.com/omsenjalia/Lib-AI.git
cd Lib-AI
flutter pub get

# drift generates lib/core/data/database.g.dart, which is not committed.
dart run build_runner build --delete-conflicting-outputs

flutter run
```

Two notes about the first build:

- **It is slow.** `fllama` vendors llama.cpp and compiles it during the build.
  On a warm machine this takes several minutes; subsequent builds reuse the
  cache.
- **Native assets must be enabled** if your Flutter build does not do it for
  you: `flutter config --enable-native-assets`.

### Model inference

The inference dependency is a **pinned git reference**, not a pub.dev package:

```yaml
fllama:
  git:
    url: https://github.com/Telosnex/fllama.git
    ref: f624e4bfaf6c354d557ddc841ae4990760819c4a
```

The package published to pub.dev as `fllama` is an unrelated, unmaintained fork
with a different API and no multimodal support. Do not replace this with
`fllama: ^0.0.1`.

---

## Build a release APK

```bash
flutter build apk --release --no-obfuscate
# build/app/outputs/flutter-apk/app-release.apk
```

Signing is driven by `SIGNING_MODE`, which the CI sets for you:

| `SIGNING_MODE` | Behaviour |
|---|---|
| `signed` | Signs with `KEYSTORE_PATH` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` |
| `debug-keys` | Signs with the debug key. Used when no keystore secret is configured |
| *(unset)* | Falls back to debug keys |

The APK is the only distribution format: no Play Store listing, no AAB.

---

## Adding or changing a model

`tool/generate_models_catalogue.py` is the **source of truth** for the catalogue.
The app never fetches the model list from the network, so this file is what makes
the app usable on a device that has never been online.

1. Add the repository and its quantisations to the script:

   ```python
   REPOS["my-model"] = {
       "hf_model_id": "org/Model-Name",
       "gguf_repo_id": "org/Model-Name-GGUF",
       ...
   }

   QUANTS["my-model"] = [
       {
           "quant": "Q4_K_M",
           "fileName": "Model-Name-Q4_K_M.gguf",
           "sizeBytes": 5736063744,
           "qualityNote": "Recommended balance of size and quality.",
           "fitsTargetDevice": True,
       },
   ]
   ```

   Sizes must be the **exact byte counts** from HuggingFace's file tree, and each
   entry needs its real SHA-256 (the tree API's `lfs.oid` is that checksum).

2. Regenerate and validate:

   ```bash
   python3 tool/generate_models_catalogue.py
   flutter test test/models/model_catalogue_test.dart
   ```

3. Never hand-edit `assets/models_catalogue.json`. The test suite validates the
   generated file: sizes against byte counts, checksums as real SHA-256 values,
   download URLs inside the model's own repository, vision claims against
   recorded evidence, and the 27B's Wi-Fi-only and High-RAM flags.

### Why one model is deliberately awkward

`Qwen3.8-27B` is in the catalogue with a **High RAM** badge, a **hard Wi-Fi-only
block** and an explicit warning that it will not load on this device. It is kept
because it is the reference model for the study use case, and hiding it would
make the library a worse comparison. It cannot be downloaded on mobile data at
all, and the app says so rather than merely advising against it.

---

## Release workflow

Three workflows run automatically, plus two on demand:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci-test.yml` | PRs, pushes to `main`/`develop` | Generate drift code, analyze, test. Failures are posted as a PR comment before the job fails |
| `ci-build-signed.yml` | PRs, pushes | Builds a signed `release.apk` and uploads it as an artifact |
| `nightly-release.yml` | Daily at 00:00 IST, or manual | If the branch moved in the last 24h, publishes a dated GitHub Release with a direct `release.apk` asset |
| `release.yml` | Tag push `v*`, or manual | Runs the tests, builds, and publishes a GitHub Release for that tag |
| `pr-check.yml` | PRs | Catalogue validation, the offline boundary check, and no-`print`/no-`TODO` guardrails |

To cut a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Optional repository secrets** for signed builds. Without them CI still
succeeds, signing with the debug key:

| Secret | Purpose |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 release.keystore` |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |

---

## Repository layout

```
lib/
  core/
    constants/    fixed values, seeded tags and personas
    data/         drift tables, AppDatabase, DAOs (database.g.dart is generated)
    errors/       typed AppExceptions that carry user-facing recovery advice
    models/       catalogue, settings and transfer value objects
    providers/    the Riverpod graph that wires the services together
    services/     inference engine, download manager, update checker, export
    theme/        Material 3 themes, dark-mode-first
    utils/        LaTeX splitting, markdown blocks, PDF text, formatters
    widgets/      shared UI (badges, tags, meters, dialogs, banners)
  features/
    chat/         chat screen, controller, message rendering, composer
    conversations/ sidebar with search, grouping and undo-delete
    model_library/ model cards, quant selector, download flow
    personas/      study persona library and editor
    notes/         "My Notes" placeholder (Phase 2)
    settings/      all preferences and storage management
tool/             catalogue generator (source of truth for model metadata)
assets/           the generated catalogue, bundled into the APK
docs/             Phase 1 research brief, verification record
test/             unit tests for pure logic, schema tests, offline eval scenarios
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for why these choices were made, how the
inference pipeline works, the full SQLite schema, and how RAG will slot in.

---

## The offline guarantee

The app must pass a full airplane-mode smoke test: chat, history, markdown,
LaTeX, code highlighting, PDF export, OCR, tags and personas.

It does, because nothing outside model management touches the network. That
claim is enforced, not just asserted: `.github/workflows/pr-check.yml` fails any
pull request that imports a networking package outside the five model-management
services.

The network is used for exactly three things, all of them yours to trigger or
observe:

1. Downloading a model you asked for.
2. Checking whether a downloaded model has changed upstream — at most once per
   model per 24 hours, never on mobile data for the 27B, and silently skipped
   when offline.
3. Nothing else. An update check can only ever produce a badge; it never
   downloads. Replacing a model file requires you to tap Update.

---

## Licence and model terms

No licence file is included, so the application code is all rights reserved by
default. Choose and add one before publishing if that is not what you want.

Model weights are **not** covered by this repository and are not bundled with the
app. Each model carries its own licence from its HuggingFace repository, listed
per model in `assets/models_catalogue.json` and shown on the model card before
you download anything.
