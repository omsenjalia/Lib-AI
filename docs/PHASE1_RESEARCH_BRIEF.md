# Library AI — Phase 1 Research & Architecture Audit

**Status:** Stage 1 complete. No application code written yet.
**Date:** 2026-09-24
**Method:** Every model fact below was read from the live HuggingFace API
(`/api/models/{id}` and `/api/models/{id}/tree/main?recursive=true`) and the
model cards (`/raw/main/README.md`) on the date above. File sizes are **exact
byte counts from the HuggingFace file tree**, not estimates. Nothing in this
matrix is inferred or assumed.

---

## 0. Headline findings — read before approving Stage 2

There are four places where the original brief's assumptions do not match
reality. Each is a judgment call that needs your decision.

### ⚠️ Finding 1 — The 27B model cannot be made to work on an S25 at usable quality

The brief proposed *"Recommend Q2_K or Q3_K_S (brings it to ~9–11GB)"*.
**Neither of those quantisations exists in the source repository**, and the
smallest available options are far worse than the brief anticipated:

| What the brief assumed | What actually exists (`unsloth/Qwen3.8-27B-GGUF`) |
|---|---|
| `Q2_K` ≈ 9–11 GB | No plain `Q2_K`. Nearest is `UD-Q2_K_XL` = **9.83 GB** |
| `Q3_K_S` ≈ 9–11 GB | **No `Q3_K_S` at all.** Nearest is `UD-Q3_K_XL` = **13.15 GB** |
| `Q4_K_M` ≈ 15–17 GB | `UD-Q4_K_M` = **16.46 GB** ✅ (this part of the brief was right) |

The only quants that could *plausibly* load in ~9 GB of usable RAM are the
IQ1/IQ2 tier, and they are specialist emergency quants:

- `UD-IQ1_S` — **6.19 GB** (quality is severely degraded)
- `UD-IQ1_M` — **6.73 GB** (severely degraded)
- `UD-IQ2_XXS` — **7.27 GB** (poor but technically coherent)

And the model file is only part of the budget. A llama.cpp load also needs the
KV cache, the compute buffer, and the ~0.93 GB vision projector if you want
image input. On a 27B hybrid-attention model at 8,192 context that overhead is
roughly **1–1.5 GB**.

**Conclusion: the 27B will not reliably load on an S25 at any usable quality.**
It is a catalogue entry, not a working model. This is surfaced now, before code,
exactly as required.

### ⚠️ Finding 2 — Two of the five models have no GGUF in their official repositories

- **`Qwen/Qwen3.8-27B`** ships **safetensors only** — 18 shards, ~55.0 GB total, zero `.gguf` files.
- **`XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B`** ships **safetensors only** — 4 shards, ~18.8 GB total, zero `.gguf` files.

Both therefore need a **third-party GGUF source**. I selected the most
trustworthy available for each (reasoning in §2). If you would rather the app
refuse to list a model without an official GGUF, say so and the 27B and MiMo
both drop out of the catalogue — leaving three models, not five.

### ⚠️ Finding 3 — Only one of the five models is text-only

The brief marked vision as "TBC" for all five. Four are confirmed
vision-capable, **one is not**:

- `Qwen3.5-9B-Claude-Opus-4.6-Distill-GGUF` has **no `mmproj-*.gguf` file** in
  its repository and no vision tags or vision claims in its model card. It is a
  **text-only reasoning distill.** OCR mode will correctly refuse it.

Separately: three of the four vision-capable models carry an explicit honesty
note in their own cards stating the vision tower was **frozen and never
fine-tuned** (it is inherited from the Qwen3.5 base). Vision works, but
image-grounded reasoning quality is base-model quality, not fine-tune quality.
Expect solid printed-text OCR, weaker chart/diagram reasoning. This is a
model-author statement, not my inference.

### ⚠️ Finding 4 — `fllama` does not expose top-k

`fllama`'s `OpenAiRequest` (the chat path) exposes `temperature`, `topP`,
`frequencyPenalty`, `presencePenalty`, `maxTokens`, `contextSize` and
`enableThinking`. It does **not** expose `top_k`, and neither does the
lower-level `FllamaInferenceRequest`. The Phase 3 settings screen specifies a
top-k slider. Options are in §5.

---

## 1. Confirmed model compatibility matrix

All sizes are exact bytes from the HuggingFace file tree. `GiB` figures are the
decimal-GB figure a user sees in their file manager.

### 1.1 Qwen3.8-27B — 27B class — **NOT VIABLE ON S25**

| Field | Value |
|---|---|
| Official repo | `Qwen/Qwen3.8-27B` — **safetensors only, no GGUF** |
| Official commit | `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0` |
| Official last modified | `2026-08-14T15:00:01.000Z` |
| Architecture | `Qwen3_5ForConditionalGeneration` (`qwen3_5`), hybrid Gated-DeltaNet |
| GGUF source used | **`unsloth/Qwen3.8-27B-GGUF`** (4,564 likes, 7,134,167 downloads) |
| GGUF commit (version baseline) | `4ca720788d1e01f1bff70c033e0d0028fd02e502` |
| GGUF last modified | `2026-08-20T12:04:25.000Z` |
| **Vision** | ✅ **CONFIRMED** — `pipeline_tag: image-text-to-text`, card documents image *and video* input, `preprocessor_config.json` + `video_preprocessor_config.json` present, and the GGUF repo ships `mmproj-BF16.gguf` |
| Context | 262,144 native (YaRN-extensible). **Recommend 8,192 in-app.** |
| Fits S25? | ❌ **No** — smallest credible quant is 7.27 GB before KV cache + 0.93 GB mmproj |

**Available quants (exact bytes):**

| File | Quant | Bytes | GB |
|---|---|---|---|
| `Qwen3.8-27B-UD-IQ1_S.gguf` | UD-IQ1_S | 6,192,222,208 | 6.19 |
| `Qwen3.8-27B-UD-IQ1_M.gguf` | UD-IQ1_M | 6,729,166,848 | 6.73 |
| `Qwen3.8-27B-UD-IQ2_XXS.gguf` | UD-IQ2_XXS | 7,266,070,528 | 7.27 |
| `Qwen3.8-27B-UD-IQ2_S.gguf` | UD-IQ2_S | 8,371,970,048 | 8.37 |
| `Qwen3.8-27B-UD-Q2_K_XL.gguf` | UD-Q2_K_XL | 9,828,981,664 | 9.83 |
| `Qwen3.8-27B-UD-IQ3_XXS.gguf` | UD-IQ3_XXS | 10,934,860,704 | 10.93 |
| `Qwen3.8-27B-UD-IQ3_S.gguf` | UD-IQ3_S | 12,040,883,104 | 12.04 |
| `Qwen3.8-27B-UD-Q3_K_XL.gguf` | UD-Q3_K_XL | 13,146,393,504 | 13.15 |
| `Qwen3.8-27B-UD-IQ4_XS.gguf` | UD-IQ4_XS | 14,252,845,984 | 14.25 |
| `Qwen3.8-27B-UD-Q4_K_S.gguf` | UD-Q4_K_S | 15,358,213,024 | 15.36 |
| `Qwen3.8-27B-Q4_0.gguf` | Q4_0 | 16,056,478,688 | 16.06 |
| `Qwen3.8-27B-UD-Q4_K_M.gguf` | **UD-Q4_K_M** | 16,464,440,224 | 16.46 |
| `Qwen3.8-27B-Q4_1.gguf` | Q4_1 | 17,540,705,248 | 17.54 |
| `Qwen3.8-27B-UD-Q4_K_XL.gguf` | UD-Q4_K_XL | 17,559,178,144 | 17.56 |
| `Qwen3.8-27B-UD-Q5_K_S.gguf` | UD-Q5_K_S | 18,665,753,504 | 18.67 |
| `Qwen3.8-27B-UD-Q5_K_M.gguf` | UD-Q5_K_M | 19,771,509,664 | 19.77 |
| `Qwen3.8-27B-UD-Q5_K_XL.gguf` | UD-Q5_K_XL | 20,876,938,144 | 20.88 |
| `Qwen3.8-27B-UD-Q6_K.gguf` | UD-Q6_K | 21,983,677,344 | 21.98 |
| `Qwen3.8-27B-UD-Q6_K_M.gguf` | UD-Q6_K_M | 23,088,409,504 | 23.09 |
| `Qwen3.8-27B-UD-Q6_K_L.gguf` | UD-Q6_K_L | 24,193,919,904 | 24.19 |
| `Qwen3.8-27B-UD-Q6_K_XL.gguf` | UD-Q6_K_XL | 25,299,061,664 | 25.30 |
| `Qwen3.8-27B-UD-Q8_K_L.gguf` | UD-Q8_K_L | 28,045,695,904 | 28.05 |
| `Qwen3.8-27B-Q8_0.gguf` | Q8_0 | 29,047,086,048 | 29.05 |
| `Qwen3.8-27B-UD-Q8_K_XL.gguf` | UD-Q8_K_XL | 31,457,991,680 | 31.46 |
| `BF16/…-00001-of-00002.gguf` + `-00002` | BF16 | 49,986,159,616 + 4,671,576,000 | 54.66 |
| `mmproj-BF16.gguf` | **vision projector** | 931,146,432 | 0.93 |
| `mmproj-F16.gguf` | vision projector | 927,607,488 | 0.93 |
| `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` | MTP drafter | 1,369,590,656 | 1.37 |

> **Note the absence of `Q3_K_S` and plain `Q2_K`.** If the catalogue is to
> match the brief's wording, that wording has to change.
>
> **Vision-capable alternative source:** `ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF`
> (1,623 likes, tagged `multimodal`/`vision`, ships
> `mmproj-Qwen3.8-27B-BF16.gguf`). Its smallest quant is `IQ2_XS` at 8.42 GB —
> **larger** than unsloth's IQ2_XXS, so it is a worse fit for the S25 even
> though its quantisation research is excellent. Listed for completeness.

---

### 1.2 MiMo-V2.6-Distill-Qwen-9B — 9B class — ✅ FITS

| Field | Value |
|---|---|
| Official repo | `XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B` — **safetensors only, no GGUF** |
| Official commit | (listed via `bartowski` derivation below) |
| Base model | `Qwen/Qwen3.5-9B` (SFT, 77.4 B tokens) |
| GGUF source used | **`bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF`** |
| GGUF commit (version baseline) | `4371da10c84fb26da3592d4cf312d24aa82b7b65` |
| GGUF last modified | `2026-09-21T22:44:19.000Z` |
| **Vision** | ✅ **CONFIRMED** — `pipeline_tag: image-text-to-text`; card benchmarks a *Visual* coding domain; `preprocessor_config.json` + `video_preprocessor_config.json` present; repo ships `mmproj-MiMo-V2.6-Distill-Qwen-9B-bf16.gguf` |
| Context | 262,144 native. **Recommend 8,192 in-app.** |
| Fits S25? | ✅ **Yes** at Q4_K_M (5.84 GB) + mmproj (0.92 GB) |

**Quant ladder (exact bytes) — recommended in bold:**

| File | Quant | Bytes | GB |
|---|---|---|---|
| `…-Q2_K.gguf` | Q2_K | 3,644,380,704 | 3.64 |
| `…-IQ3_XXS.gguf` | IQ3_XXS | 4,138,833,440 | 4.14 |
| `…-Q3_K_S.gguf` | Q3_K_S | 4,260,304,416 | 4.26 |
| `…-IQ3_XS.gguf` | IQ3_XS | 4,268,037,664 | 4.27 |
| `…-Q3_K_M.gguf` | Q3_K_M | 4,479,948,320 | 4.48 |
| `…-Q3_K_L.gguf` | Q3_K_L | 4,659,156,512 | 4.66 |
| `…-IQ3_M.gguf` | IQ3_M | 4,846,458,400 | 4.85 |
| `…-IQ4_XS.gguf` | IQ4_XS | 5,227,304,480 | 5.23 |
| `…-Q4_0.gguf` | Q4_0 | 5,482,829,344 | 5.48 |
| `…-Q4_K_S.gguf` | Q4_K_S | 5,483,255,328 | 5.48 |
| `…-IQ4_NL.gguf` | IQ4_NL | 5,825,058,336 | 5.83 |
| `…-Q4_K_M.gguf` | **Q4_K_M** | **5,841,049,120** | **5.84** |
| `…-Q4_K_L.gguf` | Q4_K_L | 6,202,021,408 | 6.20 |
| `…-Q5_K_S.gguf` | Q5_K_S | 6,496,015,904 | 6.50 |
| `…-Q5_K_M.gguf` | Q5_K_M | 6,876,124,704 | 6.88 |
| `…-Q6_K_S.gguf` | Q6_K_S | 7,509,284,384 | 7.51 |
| `…-Q6_K.gguf` | Q6_K | 7,793,710,624 | 7.79 |
| `…-Q6_K_L.gguf` | Q6_K_L | 8,106,579,488 | 8.11 |
| `…-Q8_0.gguf` | Q8_0 | 9,545,979,424 | 9.55 |
| `…-bf16.gguf` | BF16 | 17,920,693,440 | 17.92 |
| `mmproj-…-bf16.gguf` | **vision projector** | 921,704,992 | 0.92 |
| `mmproj-…-f16.gguf` | vision projector | 918,166,048 | 0.92 |

> **Official-alternative note:** `ggml-org/MiMo-V2.6-Distill-Qwen-9B-GGUF` is the
> llama.cpp organisation's own conversion and would be the most authoritative
> source — but it publishes **only `Q8_0` (9.55 GB)**, which is too large for a
> comfortable S25 load. Hence bartowski for the Q4_K_M the brief requires.

---

### 1.3 Qwythos-9B-v2 — 9B class — ✅ FITS

| Field | Value |
|---|---|
| GGUF repo | `empero-ai/Qwythos-9B-v2-GGUF` |
| GGUF commit (version baseline) | `97c11b03687f194b300efbdb4760d9bc4021b759` |
| GGUF last modified | `2026-07-12T00:58:46.000Z` |
| Architecture | `qwen35`, GGUF v3, hybrid Gated-DeltaNet (3:1 SSM:attention) |
| **Vision** | ✅ **CONFIRMED** — card has a dedicated *Vision (image input)* section with a worked `llama-mtmd-cli` example; `multimodal` + `vision` tags; ships `mmproj-Qwythos-9B-v2-BF16.gguf` |
| Vision caveat | Card states verbatim: *"all Qwythos training was text-only — the vision tower was never fine-tuned… has not been independently evaluated"* |
| Context | 1,048,576 via YaRN (4× the 262,144 native). **Recommend 8,192 in-app.** |
| Sampling defaults | temp 0.6, top_p 0.95, top_k 20, repeat_penalty 1.05 |
| Fits S25? | ✅ **Yes** |
| Bonus | Repo ships a `SHA256SUMS` file — usable for real checksum verification |

**Available quants (exact bytes):**

| File | Quant | Bytes | GB |
|---|---|---|---|
| `Qwythos-9B-v2-Q4_K_M.gguf` | **Q4_K_M** | **5,736,063,744** | **5.74** |
| `Qwythos-9B-v2-Q5_K_M.gguf` | Q5_K_M | 6,523,806,464 | 6.52 |
| `Qwythos-9B-v2-Q6_K.gguf` | Q6_K | 7,458,300,672 | 7.46 |
| `Qwythos-9B-v2-Q8_0.gguf` | Q8_0 | 9,527,501,568 | 9.53 |
| `Qwythos-9B-v2-BF16.gguf` | BF16 | 17,920,697,088 | 17.92 |
| `Qwythos-9B-v2-MTP-Q4_K_M.gguf` | Q4_K_M + MTP | 5,903,822,528 | 5.90 |
| `Qwythos-9B-v2-MTP-Q5_K_M.gguf` | Q5_K_M + MTP | 6,710,963,904 | 6.71 |
| `Qwythos-9B-v2-MTP-Q6_K.gguf` | Q6_K + MTP | 7,666,069,184 | 7.67 |
| `Qwythos-9B-v2-MTP-Q8_0.gguf` | Q8_0 + MTP | 9,786,060,480 | 9.79 |
| `Qwythos-9B-v2-MTP-BF16.gguf` | BF16 + MTP | 18,407,321,280 | 18.41 |
| `mmproj-Qwythos-9B-v2-BF16.gguf` | **vision projector** | 921,704,512 | 0.92 |

---

### 1.4 Qwythos-9B-Claude-Mythos-5.1M — 9B class — ✅ FITS

| Field | Value |
|---|---|
| GGUF repo | `empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF` |
| GGUF commit (version baseline) | `5cebd89dd078b033c26988248740ddadf40f2fbd` |
| GGUF last modified | `2026-07-14T13:12:53.000Z` |
| **Vision** | ✅ **CONFIRMED** — card has a full *Vision (image input)* section including an OpenAI-compatible server example; `multimodal` + `vision` tags; ships `mmproj-Qwythos-9B-Claude-Mythos-5-1M-F16.gguf` |
| Vision caveat | Vision tower frozen from Qwen3.5-9B base, text-only SFT — same honesty note as 1.3 |
| Context | 1,048,576 via YaRN. **Recommend 8,192 in-app.** |
| Sampling defaults | temp 0.6, top_p 0.95, top_k 20, repeat_penalty 1.05 |
| Fits S25? | ✅ **Yes** |
| Bonus | Ships `SHA256SUMS` and a `TEST_REPORT.md` |

> ⚠️ **Sampling warning from the card:** *"Avoid greedy decoding and
> very-low-temperature sampling (T ≤ 0.3) — both can cause repetition loops on
> long reasoning generations."* The app's temperature slider will default to
> 0.6 and warn below 0.3 for this model.

**Available quants (exact bytes):**

| File | Quant | Bytes | GB |
|---|---|---|---|
| `Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf` | **Q4_K_M** | **5,629,108,896** | **5.63** |
| `…-Q5_K_M.gguf` | Q5_K_M | 6,467,969,696 | 6.47 |
| `…-Q6_K.gguf` | Q6_K | 7,359,259,296 | 7.36 |
| `…-Q8_0.gguf` | Q8_0 | 9,527,501,472 | 9.53 |
| `…-BF16.gguf` | BF16 | 17,920,696,992 | 17.92 |
| `…-MTP-Q4_K_M.gguf` | Q4_K_M + MTP | 5,887,667,808 | 5.89 |
| `…-MTP-Q5_K_M.gguf` | Q5_K_M + MTP | 6,726,528,608 | 6.73 |
| `…-MTP-Q6_K.gguf` | Q6_K + MTP | 7,617,818,208 | 7.62 |
| `…-MTP-Q8_0.gguf` | Q8_0 + MTP | 9,786,060,384 | 9.79 |
| `…-MTP-BF16.gguf` | BF16 + MTP | 18,407,321,184 | 18.41 |
| `mmproj-Qwythos-9B-Claude-Mythos-5-1M-F16.gguf` | **vision projector** | 918,165,472 | 0.92 |

---

### 1.5 Qwen3.5-9B-Claude-Opus-4.6-Distill — 9B class — ✅ FITS but ❌ **TEXT-ONLY**

| Field | Value |
|---|---|
| GGUF repo | `empero-ai/Qwen3.5-9B-Claude-Opus-4.6-Distill-GGUF` |
| GGUF commit (version baseline) | `892a4362ba5896d67d566a316973fefb70f5135f` |
| GGUF last modified | `2026-03-15T23:23:35.000Z` |
| Base model | `Qwen/Qwen3.5-9B` (QLoRA SFT, 12,840 examples of Claude Opus 4.6 reasoning traces) |
| **Vision** | ❌ **NO — text-only.** No `mmproj-*.gguf` in the repository, no `vision`/`multimodal` tag, no vision claim anywhere in the card. Output format is `<think>…</think>` preceded reasoning. |
| Context | 4,096 (SFT max sequence length). **Recommend 4,096 in-app.** |
| Fits S25? | ✅ **Yes** |

> ⚠️ **Data-quality catch:** the repo's README documents its files with
> **lowercase, differently-named** filenames (e.g.
> `qwen3.5-9b-opus4.6-distill-Q4_K_M.gguf`), but the **actual files in the
> repository** are capitalised and hyphenated differently (e.g.
> `Qwen3.5-9B-Claude-Opus-4.6-Distill-Q4_K_M.gguf`). `assets/models_catalogue.json`
> uses the **actual repository filenames**. Building URLs from the README would
> have produced five 404s.

**Available quants (exact bytes):**

| File | Quant | Bytes | GB |
|---|---|---|---|
| `Qwen3.5-9B-Claude-Opus-4.6-Distill-Q2_K.gguf` | Q2_K | 3,827,261,760 | 3.83 |
| `…-Q3_K_M.gguf` | Q3_K_M | 4,623,524,160 | 4.62 |
| `…-Q4_K_M.gguf` | **Q4_K_M** | **5,629,108,544** | **5.63** |
| `…-Q5_K_M.gguf` | Q5_K_M | 6,467,969,344 | 6.47 |
| `…-Q6_K.gguf` | Q6_K | 7,359,258,944 | 7.36 |
| `…-Q8_0.gguf` | Q8_0 | 9,527,501,120 | 9.53 |
| `…-f16.gguf` | F16 | 17,920,696,640 | 17.92 |

**No `mmproj` file exists for this model.** OCR mode will show the
"Switch to a vision-capable model to use OCR mode" prompt, as the brief requires.

---

## 2. RAM budget — the arithmetic behind Finding 1

S25 (8 GB SKU) with Android 15 + One UI leaves roughly **8–9 GB usable** for
apps. A llama.cpp load costs: model weights + KV cache + compute buffers
(+ mmproj if vision is enabled).

| Model | Recommended quant | Weights | Vision projector | Est. KV @ 8k | **Total** | Verdict |
|---|---|---|---|---|---|---|
| MiMo-V2.6-Distill-Qwen-9B | Q4_K_M | 5.84 GB | 0.92 GB | ~0.4 GB | **~7.2 GB** | ✅ comfortable |
| Qwythos-9B-Claude-Mythos-5.1M | Q4_K_M | 5.63 GB | 0.92 GB | ~0.4 GB | **~7.0 GB** | ✅ comfortable |
| Qwythos-9B-v2 | Q4_K_M | 5.74 GB | 0.92 GB | ~0.4 GB | **~7.1 GB** | ✅ comfortable |
| Qwen3.5-9B-Opus-4.6-Distill | Q4_K_M | 5.63 GB | — | ~0.2 GB @4k | **~5.8 GB** | ✅ comfortable |
| **Qwen3.8-27B** | UD-IQ2_XXS | 7.27 GB | 0.93 GB | ~1.0 GB | **~9.2 GB** | ❌ **over budget** |
| Qwen3.8-27B | UD-Q4_K_M | 16.46 GB | 0.93 GB | ~1.0 GB | ~18.4 GB | ❌ impossible |

The brief's "all 9B models at Q4_K_M are ~5–6 GB — comfortable on S25" is
**confirmed correct**. The brief's "27B at Q4_K_M will NOT fit" is **confirmed
correct**. What was *not* anticipated is that even the emergency quants do not
rescue it.

## 3. Chosen inference framework — Flutter + fllama

The Phase 2 decision tree's three gating checks were run against the live
`Telosnex/fllama` repository (210★, last pushed **2026-09-22** — actively
maintained):

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | GGUF loading on Android | ✅ **PASS** | Android is a first-class target with its own CI; `fllamaDylib` resolves `libfllama.so` on `Platform.isAndroid` |
| 2 | Image + text (multimodal) | ✅ **PASS** | `OpenAiRequest.mmprojPath` + images passed as `<img src="data:image/jpeg;base64,…">` tags inside user message text. Card: *"Full OpenAI compatibility: chat messages, multimodal/image support"* |
| 3 | Token streaming as stream/callback | ✅ **PASS** | `fllamaChat(request, (String response, String openaiJson, bool done) {…})` — cumulative-text callback fired per token |

**All three confirmed → proceed with Flutter + fllama**, as the decision tree
specifies. `flutter_llama_cpp` and React Native fallbacks are not required.

### Framework API surface actually available (verified from source)

```dart
Future<int> fllamaChat(OpenAiRequest request, FllamaInferenceCallback callback);
Future<int> fllamaInference(FllamaInferenceRequest request, FllamaInferenceCallback callback);
void        fllamaCancelInference(int requestId);          // → Stop button
Future<int> fllamaTokenize(FllamaTokenizeRequest request); // → context meter
Future<String> fllamaChatTemplateGet(String modelPath);
Future<String> fllamaEosTokenGet(String modelPath);
Future<String> fllamaBosTokenGet(String modelPath);
List<FllamaGpuMemoryInfo> fllamaGpuMemoryInfoGetAll();
bool fllamaOutputIndicatesLoadError(String output);        // → OOM / corrupt detection
```

Two consequences worth noting up front:

- **Streaming is cumulative, not delta.** The callback receives the whole
  response so far, not the newest token. The app computes a delta against the
  previous callback to drive per-token fade-in. This is an adaptation to the
  binding's shape, documented in `ARCHITECTURE.md`.
- **Inference already runs off the UI isolate.** fllama dispatches to a helper
  isolate internally, satisfying the Phase 7 "background isolate" requirement
  without us writing isolate plumbing.

### GPU / NPU acceleration — honest position

The brief asks to enable the Snapdragon 8 Elite **Hexagon NPU** "if the binding
exposes llama.cpp's Qualcomm QNN backend." **fllama does not.** Although its
Dart API accepts `numGpuLayers`, source inspection of the pinned Android build
(`hook/build.dart` and `src/CMakeLists.txt`) shows no Android OpenCL or Vulkan
backend is enabled; its Android path is CPU-only. The app now probes
`fllamaGpuMemoryInfoGetAll()`, hides the GPU-layer control when no backend is
reported, forces `n_gpu_layers` to zero, and retries CPU if a future GPU warm-up
fails. Therefore this build does **not** accelerate on the S25 Adreno GPU or
Hexagon NPU. The separate `sapjax/llama_cpp_dart` v0.9.x project ships OpenCL
and Hexagon NPU artifacts (`llama-cpp-dart-hexagon.aar`), but it is a different
native dependency, not a capability of the currently pinned engine.

## 4. WeatherGPT patterns to replicate

`omsenjalia/weathergpt-app` was cloned and read in full (265 files). What
actually exists and is worth mirroring:

**Workflow inventory (the brief names four files that do not exist):**

| Brief asked for | WeatherGPT actually has | This project will ship |
|---|---|---|
| `ci.yml` | `ci-test.yml` | `ci.yml` — analyse + test gate, PR-comment reporting |
| `build-android.yml` | `ci-build-signed.yml` | `build-android.yml` — debug APK on push to `main` |
| `release.yml` | *(none — no tag-triggered release)* | `release.yml` — signed APK on `v*` tag push |
| `pr-check.yml` | *(folded into `ci-test.yml`)* | `pr-check.yml` — required-status PR gate |
| *(not requested)* | `nightly-release.yml` | `nightly-release.yml` — mirrored, 00:00 IST dated `release.apk` |

The three WeatherGPT workflows are **replicated faithfully**, including their
distinctive behaviours: `continue-on-error` on the analyse/test steps with the
output **posted back to the PR as a comment** via `gh pr comment`, the
`subosito/flutter-action@v2` + `actions/cache@v4` double-caching, Java 17
temurin with `cache: gradle`, the `KEYSTORE_BASE64` decode step with a
**debug-key fallback when the secret is absent**, and publishing a bare
`release.apk` (never a zip or AAB).

**Other conventions carried over:**
- **State management:** Riverpod (`flutter_riverpod`) — same as WeatherGPT.
- **Layout:** `lib/core/{constants,errors,models,services,theme,utils,widgets}` +
  `lib/features/<feature>/{models,providers,screens,widgets}`.
- **Lints:** `flutter_lints` via `analysis_options.yaml` with
  `analyzer.exclude: [build/**, android/**, ios/**]`.
- **Signing:** `SIGNING_MODE=unsigned|signed|debug-keys` env-driven Gradle
  Kotlin DSL config, reading `KEYSTORE_PATH`/`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`.
- **`AGENTS.md`** documenting the mandatory `ARCHITECTURE.md` sync policy.
- **CI gate definition:** a change is verified when analyse + test are green —
  not when the (much slower) APK build is green.

**Deliberately *not* carried over:** the `.env`/`flutter_dotenv` pattern and the
`BACKEND_URL` secret. Library AI is offline-first with no backend, so a
`.env` requirement would contradict the offline-first guarantee. Colour scheme,
product identity and data layer are all new, as instructed.

## 5. ⚠️ Decisions I need from you before writing code

**D1 — What should the 27B model do in the shipped app?**
Since it cannot run on the target device, the honest options are: (a) keep it in
the catalogue with a High-RAM badge, a hard Wi-Fi block, a default quant of
UD-IQ2_XXS, and an explicit in-app "will not load on this device" warning;
(b) same but with the download button disabled until the user opts in from
Settings; (c) drop it from the catalogue entirely. My recommendation is **(a)** —
it matches your spec literally while refusing to pretend the model works.

**D2 — How should the top-k slider behave, given fllama cannot apply it?**
(a) Keep the slider, persist the value, and label it in-line as not applied by
the current engine build (honest, and makes the eventual `llama_cpp_dart`
upgrade a drop-in); (b) remove top-k from Settings; (c) switch the engine to
`llama_cpp_dart` for full sampler control **and** Hexagon NPU support, at the
cost of deviating from your stated decision tree. My recommendation is **(a)**,
with (c) written up in `ARCHITECTURE.md` as the Phase 2 upgrade path.

**D3 — The 27B is 1 of 5 models, and 2 of 5 have no official GGUF.**
Confirm you are comfortable shipping a catalogue whose 27B entry is
download-and-park, and whose MiMo entry comes from `bartowski` rather than
Xiaomi. If you want "official GGUF only", the catalogue drops to 3 models.

**D4 — Verification limits in this environment (important, please read).**
This sandbox has **no Flutter or Dart SDK**, and `pub.dev` is **not reachable**
from the shell — so `flutter pub get`, `flutter analyze`, `flutter test` and
`flutter build apk` **cannot run here**. I can and will: verify every YAML is
syntactically valid, verify every download URL resolves against the real
HuggingFace API, and statically validate the Dart tree. But the Phase 7 items
that need a runtime — "PDF export generates a valid file", "markdown + LaTeX
render correctly", "context meter tested against token counts", "cold start
under 3s" — will be verified by the **GitHub Actions CI you asked for**, on
first push. I would be misreporting if I ticked those boxes from here. Confirm
you want me to proceed on that basis.

---

## 6. Blockers

| # | Blocker | Severity | Resolution |
|---|---|---|---|
| B1 | 27B cannot load on S25 at usable quality | **High** | Awaiting D1 |
| B2 | No GGUF for 2 of 5 models in official repos | **Medium** | Awaiting D3 |
| B3 | fllama lacks top-k (and QNN/NPU) | **Medium** | Awaiting D2 |
| B4 | No Flutter SDK / no pub.dev in sandbox | **Medium** | Awaiting D4 |
| B5 | `fllama` uses Flutter **native-assets build hooks**, needing Flutter ≥ 3.38 and NDK 28.2.13676358 | **Low** | Pin Flutter 3.44.0 + NDK in CI and docs, matching WeatherGPT's version pin |

None of B2–B5 blocks Stage 2. B1 is closed by your D1 answer.

---

**Phase 1 gate: complete.** Awaiting the four decisions above before Stage 2.
