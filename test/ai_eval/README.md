# Offline answer-quality evaluation

What is tested here, and what deliberately is not.

## What runs in CI

`rendering_pipeline_test.dart` pushes real-shaped model outputs through the same
code path the chat panel and the PDF exporter use:

1. `splitMessageBlocks` — decides what the markdown engine sees, what the
   highlighter sees, and what the TeX renderer sees.
2. `latexToPlainText` — the export-time conversion from LaTeX to readable text.
3. `pdfSafeText` — the transliteration needed because the built-in PDF fonts are
   WinAnsi-only.

The scenarios are:

| Scenario | Failure it guards against |
|---|---|
| Worked derivation | A display equation rendered as raw `$$...$$` source |
| Code answer | A code sample typeset as mathematics, or losing its language tag |
| Comparison table | Inline `$O(n \log n)$` breaking the markdown table |
| Model that ignores formatting rules | Undelimited LaTeX shown as raw commands, with no way to fix it |
| Mid-stream answer | An unterminated fence or `$$` crashing or swallowing the message |
| OCR-style answer | Loss of the final numeric result in the PDF export |

## What CI cannot check, and why

Rendering fidelity is not the same as answer quality, and this app answers with
weights, not with a mock. The following have to be checked on the device:

- **Does the model actually produce good answers?** Depends on the GGUF and the
  quantisation. The catalogued models are the ones Phase 1 verified; the `fits`
  flag and RAM arithmetic are in `docs/PHASE1_RESEARCH_BRIEF.md`.
- **Do formulae render correctly on screen?** `flutter_math_fork` needs a real
  rasteriser. A widget test can assert that a `Math.tex` widget is in the tree;
  only a device confirms it is legible at font scale.
- **Is the exported PDF valid and openable?** Needs a PDF reader.
- **Are the live token counts right?** `fllamaTokenize` needs a loaded model.

Per the project's D4 decision, these are verified by GitHub Actions on a real
build and by a manual pass on the Galaxy S25, not claimed from a workstation.

## Manual rubric for a device pass

Run each prompt with the model set as the default, then check:

1. **Maths** — "Solve $x^2 - 5x + 6 = 0$ step by step." Expect delimited LaTeX,
   rendered equations, and a final answer on its own line.
2. **Undelimited maths** — any answer containing `\frac`. Expect raw commands
   until "Render math" is toggled, then real maths.
3. **Code** — "Show a binary search in Dart." Expect a fenced block with
   highlighting and a working copy button.
4. **Long answer** — ask for a full essay. Expect the context meter to climb,
   turn amber past 75%, and red past 90% without stalling.
5. **Export** — export that conversation to PDF. Expect equations as readable
   text, code as monospaced text, and no missing glyphs.
6. **OCR** — photograph a question with a vision-capable model selected. Expect
   the answer to reference the image, and the model switcher to refuse a
   text-only model with an explanation.
7. **Airplane mode** — repeat 1 to 5 with the radio off. Expect no errors, no
   retry prompts and no degraded UI: the update check simply does not happen.
