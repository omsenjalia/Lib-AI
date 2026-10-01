# CLAUDE.md

Guidance for working in this repository.

## What this is

Library AI: an offline-first study assistant that runs open-weight LLMs
(llama.cpp, GGUF) entirely on an Android phone. Chat, history, markdown, LaTeX,
code highlighting, personas and PDF export work with the radio off. The network
is used only to download a model the user chose and to check whether it changed
upstream.

The repo holds two implementations of the same app:

| Path | What | Status |
|---|---|---|
| `mobile/` | **React Native (Expo SDK 57) app.** Claude-style UI, llama.rn engine | Active. New work goes here |
| `lib/`, `android/`, `test/`, `pubspec.yaml` | Flutter build (fllama engine) | Reference. Kept until the RN app is verified on a device |
| `assets/models_catalogue.json` | Model catalogue, generated | Source for both apps |
| `tool/generate_models_catalogue.py` | Catalogue generator | **Source of truth** for model metadata |
| `docs/` | UI reference inventory, research brief, verification record | Read `docs/CLAUDE_UI_INVENTORY.md` before UI work |

Architecture: [mobile/ARCHITECTURE.md](mobile/ARCHITECTURE.md) for the RN app;
[ARCHITECTURE.md](ARCHITECTURE.md) for the Flutter build and the reasoning
behind the shared rules.

## Commands (run in `mobile/`)

```bash
npm install                 # then `npm run fetch-native` if llama.rn's postinstall did not run
npm run fetch-native        # downloads llama.rn's prebuilt Android/iOS libraries
npx tsc --noEmit            # typecheck
npx expo lint               # lint
npx jest                    # unit tests (includes the offline-boundary test)
npx expo-doctor             # config/dependency checks
npx expo start --web        # browser preview of the UI (demo engine, no real model)
npx expo run:android        # dev build on a device/emulator (needs JDK 17 + Android SDK)
npx eas-cli@latest build -p android --profile preview   # cloud APK, no local JDK
```

Run typecheck, lint and tests before calling a change done. For UI changes,
also look at it in the web preview in both light and dark.

## Hard rules (do not break these)

1. **Offline boundary.** Only `src/core/services/updateChecker.ts` (metadata),
   `files.native.ts` (model transfer) and `connectivity.ts` (link state) may use
   network APIs. `__tests__/offlineBoundary.test.ts` enforces it. Do not widen
   the allowlist to make a feature work; redesign the feature.
2. **An update check never downloads.** `updateChecker.ts` must not reference
   the download manager. It only sets a flag that shows a badge.
3. **A download is not a model until its SHA-256 matches the catalogue.**
   Install rows are written only after verify plus rename.
4. **Wi-Fi-only models are blocked on mobile data before any request.** That is
   a hard gate, not a preference.
5. **Load before write.** `send()` loads the model before persisting the user's
   turn, so a failure becomes a stored error turn, never a dangling question.
6. **Never hand-edit the catalogue.** Change `tool/generate_models_catalogue.py`,
   regenerate, then copy `assets/models_catalogue.json` to
   `mobile/assets/models_catalogue.json` (`catalogue.test.ts` fails on drift).
7. **Schema changes are new migrations.** Append to `migrations` in
   `src/core/db/schema.ts`; never edit a shipped one.
8. **Keep the Flutter application id** (`com.libraryai.library_ai`) and the
   setting keys, or upgrading users lose their chats and models (see
   `legacyImport.ts`).
9. **Do not generate `android/` or `ios/` into git.** They are produced by
   `expo prebuild` from `app.json` and config plugins.

## Conventions

- **Layering.** `src/core` is React-free and takes dependencies as arguments so
  tests can pass fakes. Components talk to `src/state` stores; stores talk to
  `core`. Platform differences are separate files (`*.native.ts` /
  `*.web.ts`), not `Platform.OS` branches in shared code.
- **Errors** are `AppError` with a `recovery` line written for the student
  ("choose a smaller quantisation or lower the context length"), not a stack
  trace.
- **Styling.** Colours come from `useTheme().colors` (tokens in
  `src/theme/tokens.ts`); never raw hex in components. One accent (clay). No
  shadows, gradients or glows. Filled text buttons are ink-on-canvas because
  white on the light clay fails WCAG AA. Icons are Phosphor, regular weight.
- **Copy.** Sentence case, plain words, no exclamation marks, and no em or en
  dashes in user-visible strings.
- **Motion.** Animate transform and opacity only. Timed ease-out for travel
  (sheets, drawer), springs for presses. Respect reduced motion. Write shared
  values with `.set()`.
- **Tests** live in `mobile/__tests__/`. Logic that can be pure should be pure
  and tested there; the Flutter `test/` suite is the reference for edge cases.

## Gotchas

- **Windows:** llama.rn's native downloader shells out to `tar`. Under Git Bash
  that is GNU tar, which reads `C:\` as a remote host and fails. Run
  `npm run fetch-native` from PowerShell or cmd.
- **npm 11 install-script gating** can skip llama.rn's postinstall silently.
  If `node_modules/llama.rn/android/src/main/jniLibs` is missing, run
  `npm run fetch-native`.
- **TypeScript 6** defaults `types` to `[]`; jest and node types are listed
  explicitly in `tsconfig.json`.
- **Web preview database is sql.js, not expo-sqlite.** expo-sqlite's web build
  always sets up OPFS storage, which one tab at a time can hold; a second tab
  then fails with "Invalid VFS state". `src/core/db/driver.web.ts` uses sql.js
  in memory instead (`driver.native.ts` is expo-sqlite). The preview's engine
  (`backend.web.ts`) streams a canned showcase answer; downloads are disabled.
- **react-native-web ignores the `pointerEvents` prop;** put it in `style`.
  An invisible full-screen scrim with the prop silently eats every tap on web.
- **Release signing:** `mobile/scripts/configure-android-release.cjs` patches the
  prebuilt `android/app/build.gradle`; `__tests__/fixtures/expo57-build.gradle.txt`
  is the real Expo 57 template it is tested against. After an Expo upgrade,
  regenerate that fixture from `expo prebuild` and rerun the tests.
- **KaTeX fonts are generated code.** `src/components/chat/katexCss.generated.ts`
  comes from `node scripts/build-katex-css.mjs`. Rerun it after upgrading
  `katex`; never edit it by hand.
- **Web preview composer:** Enter sends, Shift+Enter is a new line. The
  textarea height is tracked by hand because react-native-web does not
  auto-grow it.
- `expo-notifications` cannot draw a progress bar or keep a foreground
  service; download progress is text in an ongoing notification.

## Where things are

| I want to... | Look at |
|---|---|
| Change what is sent to the model | `src/core/prompt.ts` |
| Change load or generation behaviour | `src/core/engine/engine.ts`, `backend.native.ts` |
| Change the send/stream/flush flow | `src/state/chat.ts` |
| Touch downloads, resume, checksums | `src/core/services/downloadManager.ts` (+ its test) |
| Change how replies render | `src/core/utils/markdownBlocks.ts`, `src/components/chat/{Markdown,CodeBlock,MathBlock,ThinkBlock}.tsx` |
| Change the token / tok/s readout | `src/components/chat/TokenStats.tsx`, `src/core/streamStats.ts`, `src/state/chat.ts` |
| Change the web preview's sample answer | `src/core/engine/demoShowcase.ts` |
| Add a setting | `src/core/settings.ts`, `src/app/settings.tsx` |
| Add a table or column | `src/core/db/schema.ts` (new migration), `database.ts`, `types.ts` |
| Restyle | `src/theme/tokens.ts`, `src/components/ui/primitives.tsx` |
