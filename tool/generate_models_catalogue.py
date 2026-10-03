#!/usr/bin/env python3
"""Generate assets/models_catalogue.json for Library AI.

Every size in this file is an EXACT byte count read from the HuggingFace file
tree API on 2026-09-24:

    GET https://huggingface.co/api/models/{repo}/tree/main?recursive=true

Version baselines come from:

    GET https://huggingface.co/api/models/{repo}?expand[]=sha&expand[]=lastModified

Run with:  python3 tool/generate_models_catalogue.py
Do NOT hand-edit assets/models_catalogue.json; edit this file and re-run.
"""

import json
import os

RESOLVE = "https://huggingface.co/{repo}/resolve/main/{fname}"

REPOS = {
    # The user-supplied id `bartowski/Phi-4-mini-instruct-GGUF` does not exist
    # (404). bartowski's convention is to prefix the upstream org with an
    # underscore, so the real repository is the one below - confirmed against
    # the HF API, which returns this id and not the other.
    "phi-4-mini-3.8b": dict(
        repo="bartowski/microsoft_Phi-4-mini-instruct-GGUF",
        sha="7ff82c2aaa4dde30121698a973765f39be5288c0",
        last_modified="2025-02-28T15:56:14.000Z",
        likes=46,
        downloads=48878,
    ),
    # Added 2026-10-01 for devices with only 4-5 GB free at load time. All four
    # are general.architecture=qwen35 (read from each GGUF header), which
    # llama.rn 0.13.0-rc.6 (llama.cpp b11192) supports.
    "qwen3.5-4b": dict(
        repo="unsloth/Qwen3.5-4B-GGUF",
        sha="e87f176479d0855a907a41277aca2f8ee7a09523",
        last_modified="2026-03-02T14:08:17.000Z",
        likes=446,
        downloads=1013661,
    ),
    "qwen3.5-2b": dict(
        repo="unsloth/Qwen3.5-2B-GGUF",
        sha="f6d5376be1edb4d416d56da11e5397a961aca8ae",
        last_modified="2026-03-02T14:07:35.000Z",
        likes=158,
        downloads=322275,
    ),
    "qwen3.5-4b-opus-4.6-distill": dict(
        repo="Jackrong/Qwen3.5-4B-Claude-4.6-Opus-Reasoning-Distilled-GGUF",
        sha="cd70250b528abda79bc0390af5031c40e0a73edc",
        last_modified="2026-04-06T02:08:54.000Z",
        likes=169,
        downloads=179580,
    ),
    # bartowski's imatrix conversion of empero's Qwythos-9B-v2. empero's own
    # repo stops at Q4_K_M (5.74 GB); this one goes down to IQ2_M.
    "qwythos-9b-v2-compact": dict(
        repo="bartowski/empero-ai_Qwythos-9B-v2-GGUF",
        sha="3f233570b07f7a3bc2570b975cbb210fec72efb4",
        last_modified="2026-07-19T02:38:42.000Z",
        likes=4,
        downloads=2755,
    ),
    # Gemma 4 E-series, added 2026-10-03. unsloth's QAT builds: Google trained
    # these checkpoints to be quantised to 4 bits, so the Q4 file keeps close to
    # bf16 quality and is smaller than a plain Q4_K_M (E4B: 4.22 vs 4.98 GB).
    # general.architecture=gemma4 and the projector is gemma4v, both supported
    # by llama.rn 0.13.0-rc.6.
    "gemma-4-e4b": dict(
        repo="unsloth/gemma-4-E4B-it-qat-GGUF",
        sha="8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265",
        last_modified="2026-07-17T12:37:02.000Z",
        likes=211,
        downloads=476353,
    ),
    "gemma-4-e2b": dict(
        repo="unsloth/gemma-4-E2B-it-qat-GGUF",
        sha="66a399f68ddd113b06dff02fca9523e55465d11d",
        last_modified="2026-07-17T12:36:37.000Z",
        likes=86,
        downloads=414054,
    ),
}

# (file_name, quant_label, size_bytes, quality_note[, fits_9gb])
QUANTS = {
    "phi-4-mini-3.8b": [
        ("microsoft_Phi-4-mini-instruct-IQ2_M.gguf", "IQ2_M", 1507424640, "Smallest. Relatively low quality, but usable.", True),
        ("microsoft_Phi-4-mini-instruct-IQ3_XXS.gguf", "IQ3_XXS", 1678866816, "Comparable to the Q3 quants.", True),
        ("microsoft_Phi-4-mini-instruct-Q2_K.gguf", "Q2_K", 1682636160, "Very low quality but surprisingly usable.", True),
        ("microsoft_Phi-4-mini-instruct-Q2_K_L.gguf", "Q2_K_L", 1831483776, "Q8_0 embeddings and output. Very low quality.", True),
        ("microsoft_Phi-4-mini-instruct-IQ3_XS.gguf", "IQ3_XS", 1840708992, "Slightly better than Q3_K_S.", True),
        ("microsoft_Phi-4-mini-instruct-Q3_K_S.gguf", "Q3_K_S", 1897332096, "Low quality, not recommended by the author.", True),
        ("microsoft_Phi-4-mini-instruct-IQ3_M.gguf", "IQ3_M", 2017656192, "Medium-low quality; comparable to Q3_K_M.", True),
        ("microsoft_Phi-4-mini-instruct-Q3_K_M.gguf", "Q3_K_M", 2117533056, "Low quality.", True),
        ("microsoft_Phi-4-mini-instruct-IQ4_XS.gguf", "IQ4_XS", 2224487808, "Good quality/size balance.", True),
        ("microsoft_Phi-4-mini-instruct-Q3_K_L.gguf", "Q3_K_L", 2249653632, "Lower quality but usable where RAM is tight.", True),
        ("microsoft_Phi-4-mini-instruct-IQ4_NL.gguf", "IQ4_NL", 2325151104, "Slightly larger than IQ4_XS, repacks on ARM.", True),
        ("microsoft_Phi-4-mini-instruct-Q4_0.gguf", "Q4_0", 2331442560, "Legacy 4-bit. Repacks online on ARM.", True),
        ("microsoft_Phi-4-mini-instruct-Q4_K_S.gguf", "Q4_K_S", 2337734016, "Good quality/size balance.", True),
        ("microsoft_Phi-4-mini-instruct-Q3_K_XL.gguf", "Q3_K_XL", 2398501248, "Q8_0 embeddings; lower quality, low RAM.", True),
        ("microsoft_Phi-4-mini-instruct-Q4_K_M.gguf", "Q4_K_M", 2491874688, "RECOMMENDED. Author's stated default size for most use cases.", True),
        ("microsoft_Phi-4-mini-instruct-Q4_1.gguf", "Q4_1", 2526477696, "Legacy format, similar to Q4_K_S.", True),
        ("microsoft_Phi-4-mini-instruct-Q4_K_L.gguf", "Q4_K_L", 2640722304, "Q8_0 embeddings; a little better than Q4_K_M.", True),
        ("microsoft_Phi-4-mini-instruct-Q5_K_S.gguf", "Q5_K_S", 2727804288, "High quality, small enough for an 8 GB device.", True),
        ("microsoft_Phi-4-mini-instruct-Q5_K_M.gguf", "Q5_K_M", 2848128384, "High quality. Comfortable here, unlike on the 9B models.", True),
        ("microsoft_Phi-4-mini-instruct-Q5_K_L.gguf", "Q5_K_L", 2996976000, "Q8_0 embeddings; high quality.", True),
        ("microsoft_Phi-4-mini-instruct-Q6_K.gguf", "Q6_K", 3155623296, "Near-perfect quality and still fits an 8 GB device.", True),
        ("microsoft_Phi-4-mini-instruct-Q6_K_L.gguf", "Q6_K_L", 3304470912, "Near-perfect quality, Q8_0 embeddings.", True),
        ("microsoft_Phi-4-mini-instruct-Q8_0.gguf", "Q8_0", 4084611456, "Near-lossless. The largest quant here, and it still fits.", True),
    ],
    "qwen3.5-4b": [
        ("Qwen3.5-4B-UD-IQ2_XXS.gguf", "UD-IQ2_XXS", 1520217248, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-4B-UD-IQ2_M.gguf", "UD-IQ2_M", 1759997088, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-4B-UD-Q2_K_XL.gguf", "UD-Q2_K_XL", 1940825248, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-4B-UD-IQ3_XXS.gguf", "UD-IQ3_XXS", 1949047968, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B-Q3_K_S.gguf", "Q3_K_S", 2105791648, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B-Q3_K_M.gguf", "Q3_K_M", 2293388448, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B-UD-Q3_K_XL.gguf", "UD-Q3_K_XL", 2436420768, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B-IQ4_XS.gguf", "IQ4_XS", 2477053088, "Good quality/size balance.", True),
        ("Qwen3.5-4B-IQ4_NL.gguf", "IQ4_NL", 2579944608, "Good quality/size balance.", True),
        ("Qwen3.5-4B-Q4_0.gguf", "Q4_0", 2583221408, "Good quality/size balance.", True),
        ("Qwen3.5-4B-Q4_K_S.gguf", "Q4_K_S", 2590430368, "Good quality/size balance.", True),
        ("Qwen3.5-4B-Q4_K_M.gguf", "Q4_K_M", 2740937888, "RECOMMENDED. Best balance for a 4-5 GB free-RAM budget.", True),
        ("Qwen3.5-4B-Q4_1.gguf", "Q4_1", 2784416928, "Good quality/size balance.", True),
        ("Qwen3.5-4B-UD-Q4_K_XL.gguf", "UD-Q4_K_XL", 2912109728, "Good quality/size balance.", True),
        ("Qwen3.5-4B-Q5_K_S.gguf", "Q5_K_S", 3024934048, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-4B-Q5_K_M.gguf", "Q5_K_M", 3143656608, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-4B-UD-Q5_K_XL.gguf", "UD-Q5_K_XL", 3250869408, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-4B-Q6_K.gguf", "Q6_K", 3525956768, "Near-perfect quality.", True),
        ("Qwen3.5-4B-UD-Q6_K_XL.gguf", "UD-Q6_K_XL", 4145548448, "Near-perfect quality.", True),
        ("Qwen3.5-4B-Q8_0.gguf", "Q8_0", 4482403488, "Near-lossless. Largest quant listed.", True),
        ("Qwen3.5-4B-UD-Q8_K_XL.gguf", "UD-Q8_K_XL", 5952048288, "Near-lossless. Largest quant listed.", True),
    ],
    "qwen3.5-2b": [
        ("Qwen3.5-2B-UD-IQ2_XXS.gguf", "UD-IQ2_XXS", 768270592, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-2B-UD-IQ2_M.gguf", "UD-IQ2_M", 859857152, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-2B-UD-IQ3_XXS.gguf", "UD-IQ3_XXS", 931823872, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-2B-UD-Q2_K_XL.gguf", "UD-Q2_K_XL", 966533376, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-2B-Q3_K_S.gguf", "Q3_K_S", 1030947072, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-2B-Q3_K_M.gguf", "Q3_K_M", 1107149056, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-2B-UD-Q3_K_XL.gguf", "UD-Q3_K_XL", 1159274752, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-2B-IQ4_XS.gguf", "IQ4_XS", 1172996352, "Good quality/size balance.", True),
        ("Qwen3.5-2B-IQ4_NL.gguf", "IQ4_NL", 1213300992, "Good quality/size balance.", True),
        ("Qwen3.5-2B-Q4_0.gguf", "Q4_0", 1214873856, "Good quality/size balance.", True),
        ("Qwen3.5-2B-Q4_K_S.gguf", "Q4_K_S", 1217757440, "Good quality/size balance.", True),
        ("Qwen3.5-2B-Q4_K_M.gguf", "Q4_K_M", 1280835840, "RECOMMENDED. Best balance for a 4-5 GB free-RAM budget.", True),
        ("Qwen3.5-2B-Q4_1.gguf", "Q4_1", 1293517056, "Good quality/size balance.", True),
        ("Qwen3.5-2B-UD-Q4_K_XL.gguf", "UD-Q4_K_XL", 1339752704, "Good quality/size balance.", True),
        ("Qwen3.5-2B-Q5_K_S.gguf", "Q5_K_S", 1384546560, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-2B-Q5_K_M.gguf", "Q5_K_M", 1435238656, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-2B-UD-Q5_K_XL.gguf", "UD-Q5_K_XL", 1466687744, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-2B-Q6_K.gguf", "Q6_K", 1574961408, "Near-perfect quality.", True),
        ("Qwen3.5-2B-UD-Q6_K_XL.gguf", "UD-Q6_K_XL", 1864483072, "Near-perfect quality.", True),
        ("Qwen3.5-2B-Q8_0.gguf", "Q8_0", 2012012800, "Near-lossless. Largest quant listed.", True),
        ("Qwen3.5-2B-UD-Q8_K_XL.gguf", "UD-Q8_K_XL", 2834940160, "Near-lossless. Largest quant listed.", True),
    ],
    "qwen3.5-4b-opus-4.6-distill": [
        ("Qwen3.5-4B.Q2_K.gguf", "Q2_K", 1797501760, "Very low bit. Noticeable quality loss.", True),
        ("Qwen3.5-4B.Q3_K_S.gguf", "Q3_K_S", 2069875520, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B.Q3_K_M.gguf", "Q3_K_M", 2257472320, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B.Q3_K_L.gguf", "Q3_K_L", 2358397760, "Low bit. Workable when RAM is tight.", True),
        ("Qwen3.5-4B.Q4_K_S.gguf", "Q4_K_S", 2557002560, "Good quality/size balance.", True),
        ("Qwen3.5-4B.Q4_K_M.gguf", "Q4_K_M", 2707510080, "RECOMMENDED. Best balance for a 4-5 GB free-RAM budget.", True),
        ("Qwen3.5-4B.Q5_K_S.gguf", "Q5_K_S", 2990031680, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-4B.Q5_K_M.gguf", "Q5_K_M", 3108754240, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-4B.Q6_K.gguf", "Q6_K", 3464051520, "Near-perfect quality.", True),
        ("Qwen3.5-4B.Q8_0.gguf", "Q8_0", 4482399040, "Near-lossless. Largest quant listed.", True),
    ],
    "qwythos-9b-v2-compact": [
        ("empero-ai_Qwythos-9B-v2-IQ2_M.gguf", "IQ2_M", 3906351648, "Very low bit. Noticeable quality loss.", True),
        ("empero-ai_Qwythos-9B-v2-Q2_K.gguf", "Q2_K", 4201198112, "Very low bit. Noticeable quality loss.", True),
        ("empero-ai_Qwythos-9B-v2-IQ3_XXS.gguf", "IQ3_XXS", 4412944928, "RECOMMENDED. Text-only chat fits in about 5 GB free; image input needs about 6 GB.", True),
        ("empero-ai_Qwythos-9B-v2-IQ3_XS.gguf", "IQ3_XS", 4697453088, "Low bit. Workable when RAM is tight.", True),
        ("empero-ai_Qwythos-9B-v2-Q3_K_S.gguf", "Q3_K_S", 4806242848, "Low bit. Workable when RAM is tight.", True),
        ("empero-ai_Qwythos-9B-v2-IQ3_M.gguf", "IQ3_M", 4859458080, "Low bit. Workable when RAM is tight.", True),
        ("empero-ai_Qwythos-9B-v2-Q3_K_M.gguf", "Q3_K_M", 5057114656, "Low bit. Workable when RAM is tight.", True),
        ("empero-ai_Qwythos-9B-v2-Q2_K_L.gguf", "Q2_K_L", 5194478112, "Q2_K with Q8_0 embeddings. Larger than Q3_K_M for less quality; listed for completeness.", True),
        ("empero-ai_Qwythos-9B-v2-Q3_K_L.gguf", "Q3_K_L", 5247955488, "Low bit. Workable when RAM is tight.", True),
        ("empero-ai_Qwythos-9B-v2-IQ4_XS.gguf", "IQ4_XS", 5379568160, "Good quality/size balance.", True),
    ],
    "gemma-4-e4b": [
        ("gemma-4-E4B-it-qat-UD-Q2_K_XL.gguf", "UD-Q2_K_XL", 3219532192, "Smallest. 2-bit on top of QAT; noticeable quality loss.", True),
        ("gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf", "UD-Q4_K_XL", 4215695776, "RECOMMENDED. QAT 4-bit, close to full-precision quality.", True),
    ],
    "gemma-4-e2b": [
        ("gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf", "UD-Q2_K_XL", 2186186784, "Smallest. 2-bit on top of QAT; noticeable quality loss.", True),
        ("gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf", "UD-Q4_K_XL", 2620370976, "RECOMMENDED. QAT 4-bit, close to full-precision quality.", True),
    ],
}

# SHA-256 of every file below.
#
# Source: the `lfs.oid` field returned by
#   GET https://huggingface.co/api/models/{repo}/tree/main?recursive=true
# For files stored in HuggingFace's LFS, `lfs.oid` IS the SHA-256 of the file
# contents. This was verified against the blob pages for the five recommended
# quants, e.g. Qwen3.8-27B-UD-IQ2_XXS.gguf -> "SHA256: e792d8fb3142fe...
# 645e67d", byte-identical to the tree API's lfs.oid for that path.
#
# These checksums are what the download manager verifies after transfer, and
# what breaks the tie when deciding whether a remote file has changed.
SHA256 = {
    # empero-ai/Qwythos-9B-v2-GGUF (projector only; used by qwythos-9b-v2-compact)
    "mmproj-Qwythos-9B-v2-BF16.gguf": "0d1687cb33124c78acab788b342d4a2eaf85b3035e87c3abe4ee9d0b84ddb4f5",
    # bartowski/microsoft_Phi-4-mini-instruct-GGUF
    "microsoft_Phi-4-mini-instruct-IQ2_M.gguf": "33c12b44229a85d88a3bedfe849e138643bbde5478925d191faeb409bc2ea3ec",
    "microsoft_Phi-4-mini-instruct-IQ3_M.gguf": "0d6a07d53a3ebd474a8ca9abc9415af39e88f041cfbfe388e3bf632b84e7b232",
    "microsoft_Phi-4-mini-instruct-IQ3_XS.gguf": "a94bcca75234c1775025a319a1765e3c61c5b18298d0314633f7f7524356ec2e",
    "microsoft_Phi-4-mini-instruct-IQ3_XXS.gguf": "80c87df8ba98f4e02f5e3bb8b71cab541dafb601ef071a195a4df38c56e213d7",
    "microsoft_Phi-4-mini-instruct-IQ4_NL.gguf": "c75b97730ea19e533d5a5fcbb695984bfd6278e170bf49e1251ea4f5e85b7763",
    "microsoft_Phi-4-mini-instruct-IQ4_XS.gguf": "88f5f428d64ea04332eaf3dc19d05ad4df3e04847ad9d2b0e3c947233f361a56",
    "microsoft_Phi-4-mini-instruct-Q2_K.gguf": "85134b59572e8726252f02bae6476ed6cf8c3109f5dc05da363965430157608d",
    "microsoft_Phi-4-mini-instruct-Q2_K_L.gguf": "b233015a8c8fbd13f080cbebc9a8dc496c2ce52faed06d17fb0963192e0378b5",
    "microsoft_Phi-4-mini-instruct-Q3_K_L.gguf": "d04c6c4014f24f56dc3341aa69e198815f2931a8769aeb630ced541f792889b4",
    "microsoft_Phi-4-mini-instruct-Q3_K_M.gguf": "514a111e3b847b1698b253bf8e8ada7c1bb81dc10dc4bccab590edaff5aec06c",
    "microsoft_Phi-4-mini-instruct-Q3_K_S.gguf": "a1dd4dc181bd94e896a947dbf413f04d9cce2b962a22fe363812a28b5ac34826",
    "microsoft_Phi-4-mini-instruct-Q3_K_XL.gguf": "d95f8462d750d574db0c60ed5e83c551a42d94da99b4a5f85d54b5bbbf0c14e0",
    "microsoft_Phi-4-mini-instruct-Q4_0.gguf": "2124412a2d3410dd05c5d01796457283812210633165a2a86c909f815971518e",
    "microsoft_Phi-4-mini-instruct-Q4_1.gguf": "788a028447e152719d2673930fdfb0df5f73cc134b666915565492e32fe93f26",
    "microsoft_Phi-4-mini-instruct-Q4_K_L.gguf": "ea4e670db872d1cf505e02bf8f85745ce98a564c1429fc3609cc9462089da13e",
    "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf": "01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2",
    "microsoft_Phi-4-mini-instruct-Q4_K_S.gguf": "d75c4e4a4a4f9c775ca5fec8802e7a65bbbe9241034f5b39e6a8d092f3805880",
    "microsoft_Phi-4-mini-instruct-Q5_K_L.gguf": "9e2c332c023f50ae7ed5fd51c8ca3ed846e364ad8a98471da99603082509734b",
    "microsoft_Phi-4-mini-instruct-Q5_K_M.gguf": "840ad85cff01e41701e2b2a3826016916f8e51242c8f25d62e59fa7eb93acbc5",
    "microsoft_Phi-4-mini-instruct-Q5_K_S.gguf": "b027246d847c6d6c5419a14885256061e911cc864001820b16e037868d43d090",
    "microsoft_Phi-4-mini-instruct-Q6_K.gguf": "59dba927b98f39c26859aab7fb27d5f577666f8a5db38f0eccf3f207902ba23b",
    "microsoft_Phi-4-mini-instruct-Q6_K_L.gguf": "ad6e8f3dbaca28a7d8c269058bd6ba543b7d0932be06927f847f24c9bb0d8408",
    "microsoft_Phi-4-mini-instruct-Q8_0.gguf": "a12f242c4ee379b9da91673e5d78b30bfacfe4fd86a0b2259d2ecad5d93cb6c7",
}

# Checksums for repositories added later, keyed by model id first.
#
# The flat SHA256 table above is keyed by file name alone, which only works
# while names are unique across repos. They are not: unsloth names every
# projector `mmproj-BF16.gguf`, and each one has different contents. A lookup
# here wins over the flat table. Same source: the tree API's `lfs.oid`, read
# 2026-10-01.
SHA256_BY_MODEL = {
    "gemma-4-e4b": {
        "gemma-4-E4B-it-qat-UD-Q2_K_XL.gguf": "79dde517866cfbb5c00230b530de17910fc7fc78f8827554d0e14281ce5faf03",
        "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf": "df0fd4ee07072c607c29a0a1cb4f98918426cca12f45a2776bdd6ee6d09a4de3",
        "mmproj-BF16.gguf": "7c9bafa27f82d658eda805c1d82ef62bb0368e1ff75f64f77de58ad318beaaf9",
    },
    "gemma-4-e2b": {
        "gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf": "0a5bbc20f91f92da96ab4870fa71b356c45b8500a7b8b9c3e0eb48359b72da28",
        "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf": "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889",
        "mmproj-BF16.gguf": "38b33846f56426cd650e0e574d78de125abdfcedf35c0d7f6929f6ffe26efe02",
    },
    "qwen3.5-4b": {
        "Qwen3.5-4B-IQ4_NL.gguf": "ff5c3e9740a5aa53f04fdf3b0b8cc75da556bf8948cdb19d61c512d3a43465d9",
        "Qwen3.5-4B-IQ4_XS.gguf": "658a9e7e406deb06d0179755e3c14f6a82915a4be4962a2f92a64d948d2e572f",
        "Qwen3.5-4B-Q3_K_M.gguf": "d6981ab4d77ba712b48ef69d69042d75b5e39b9dce5fb5a5b054fd08e06afb95",
        "Qwen3.5-4B-Q3_K_S.gguf": "7e2dd96b6141226b62fa88c775db06e0e9ff0aa84130805d7091a768868a3353",
        "Qwen3.5-4B-Q4_0.gguf": "298fcb5fe7a77ccc79745ae24751560c5ac56874caff4bb39b1f2055bd72b8bb",
        "Qwen3.5-4B-Q4_1.gguf": "af1fa652b5c78980b105a2ffef954bfa724bc4d69d2d44463e27c4f3c2953bbd",
        "Qwen3.5-4B-Q4_K_M.gguf": "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
        "Qwen3.5-4B-Q4_K_S.gguf": "27caeb0e4b999d92ce0a9fdbdd1a7ba5112908d9de125645883732274be2ea77",
        "Qwen3.5-4B-Q5_K_M.gguf": "8814232b85594dcd46c50e5b8b29324a7efe9e746edbe8a3d1df3d3fce7aad39",
        "Qwen3.5-4B-Q5_K_S.gguf": "161be121617c45ea247eae0fd4477d26f287a368b52702e3fc99c9bc52f23061",
        "Qwen3.5-4B-Q6_K.gguf": "fdedd781c9ce676ab66b018ca247ff78e8a33c98098a822c1e2d5075e7718f66",
        "Qwen3.5-4B-Q8_0.gguf": "10cc391b403021dd11c614679d2fd92f611c3681d29e29651b717316965d61e1",
        "Qwen3.5-4B-UD-IQ2_M.gguf": "cb4c45ca42c0d7777667e94e3963f8e59e939b3665098328ce601feb5be129c1",
        "Qwen3.5-4B-UD-IQ2_XXS.gguf": "4c1ba794e8d6098f4fb6482b4db6e880c80b5ee0b4c64d8668afaf9541163677",
        "Qwen3.5-4B-UD-IQ3_XXS.gguf": "00aab66a2359a9afc52f0ab757e61f9be1656e6fcaba8468bd95579a8b2cbc40",
        "Qwen3.5-4B-UD-Q2_K_XL.gguf": "79aa0b583c888976013002f66b9f617070d91cf8de6a09dc775983640ac59463",
        "Qwen3.5-4B-UD-Q3_K_XL.gguf": "1874727e4bb6ac23fd0cd134ac6562d2759fe44f37fa68c55197b36526da4e37",
        "Qwen3.5-4B-UD-Q4_K_XL.gguf": "b252c5610a42ca82d20fe2a12813e9d069eed89292907e26c783eeb0bc961bc7",
        "Qwen3.5-4B-UD-Q5_K_XL.gguf": "b4c36a8e14a80c21bcab5a067ce342b2e70e28f60b4aa95ad12203fa17b87426",
        "Qwen3.5-4B-UD-Q6_K_XL.gguf": "87f58d94410b81429268d8389a3d686e6c6bffecf7852772720fbea059cbbb9d",
        "Qwen3.5-4B-UD-Q8_K_XL.gguf": "e786a3c6570474c3885199bfb5adc54325aa7521a314e10b0aaefe16a54ba42f",
        "mmproj-BF16.gguf": "302b92d565080b9cc0281186979ae75a7429ec23d14f6f7607a035539b21f3a6",
    },
    "qwen3.5-2b": {
        "Qwen3.5-2B-IQ4_NL.gguf": "e430d87ebc5abbb269c2e2461f1a49b9c5dc79847c13c786dc3615d0b116c4ba",
        "Qwen3.5-2B-IQ4_XS.gguf": "3639f34b5ca22aa1c51f3616566eae8c355111554f6924ad97ee2652ed11c1cd",
        "Qwen3.5-2B-Q3_K_M.gguf": "8b049f98461020b7e15797e13413fc63b9b500ffa883c74618b618ecbc2bfccf",
        "Qwen3.5-2B-Q3_K_S.gguf": "21026bce70a757887bce861047c26966109206ebe2adeb7b662de9a179952d28",
        "Qwen3.5-2B-Q4_0.gguf": "cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1",
        "Qwen3.5-2B-Q4_1.gguf": "93a49bfdb0619305584b81608a2d8c931fdcfc0bd4b0d75f25ac2d8988199278",
        "Qwen3.5-2B-Q4_K_M.gguf": "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
        "Qwen3.5-2B-Q4_K_S.gguf": "56eee7b85a2023ba393c5f9a5a5e372e3645e7925a13adb4d13723fc5bc14124",
        "Qwen3.5-2B-Q5_K_M.gguf": "1885b3a9195f8cc09da9a7a7a75afdc1e8d5cbf9fc4a499c3961dddea37098ac",
        "Qwen3.5-2B-Q5_K_S.gguf": "5503c57f038bd201e0583d64d50d4aebba2f628004834cb4d32abb141eb1bfda",
        "Qwen3.5-2B-Q6_K.gguf": "fc90339420b4298887aafb307a4291c55440b730133bbffe6ba9630503dcb548",
        "Qwen3.5-2B-Q8_0.gguf": "1b04acba824817554f4ce23639bc8495ff70453b8fcb047900c731521021f2c1",
        "Qwen3.5-2B-UD-IQ2_M.gguf": "7df5673b6c1a8efb3b5f5988a506d991ab936b3e00ad29f94e0f75cfbf8599da",
        "Qwen3.5-2B-UD-IQ2_XXS.gguf": "43aedbd2b03a3c2cc39f49ccf74fcd3c394ed0b2a1ede8a30ee652ee9cfc27ef",
        "Qwen3.5-2B-UD-IQ3_XXS.gguf": "36347f47f9eab7d433c7c37be1f87ac2253378c3d530da3cb25fb5f71f8f1a58",
        "Qwen3.5-2B-UD-Q2_K_XL.gguf": "dbcf28421dece9c86884f9da5a2291c8214be7920623f1fcb663ed8f58b38ccb",
        "Qwen3.5-2B-UD-Q3_K_XL.gguf": "d34e1271b7ca784d739b2b7e804bac391d7b6471e695d88e8c79eae0df032263",
        "Qwen3.5-2B-UD-Q4_K_XL.gguf": "0af96165ea615bea39a04118d63f0b6d35908aea850ee4a51aa6151d851b8b35",
        "Qwen3.5-2B-UD-Q5_K_XL.gguf": "67bff9774bc55e44af2eee3c448dc054478b45c0607858fc6df5b336b55f36f4",
        "Qwen3.5-2B-UD-Q6_K_XL.gguf": "2f956e57c27b3f257916825d9d3bc174269f3df9c6fcf87a64da666c0e7a518a",
        "Qwen3.5-2B-UD-Q8_K_XL.gguf": "a53988df91157d78acaf3c95e22db179d13f6236061bdb86576494dc99b1bc3b",
        "mmproj-BF16.gguf": "f17196c0d8fc756bc65be60075bd4a359917eee8a438505639511727c585d3c2",
    },
    "qwen3.5-4b-opus-4.6-distill": {
        "Qwen3.5-4B.Q2_K.gguf": "7ee61cf5d8688ab6b7589bdee3e6ae6f7030a7b724357920eecc4e13b37435c6",
        "Qwen3.5-4B.Q3_K_L.gguf": "8287b2a5796caaf3ea6446abe82f8aff09068bf325c354f9d68c0f6a5c00c471",
        "Qwen3.5-4B.Q3_K_M.gguf": "c14a60110056fe5c44f079159b5df435fe3e7f0c0d9938e62af1a9c5ab7881cf",
        "Qwen3.5-4B.Q3_K_S.gguf": "daa6ac0be3b36d877fcbfd13db8fa0726da6e5edc75b100ec99a3db39efb4574",
        "Qwen3.5-4B.Q4_K_M.gguf": "e1a4a9886699fecb153747ae97aeb413a7e6bd69da80037aa66cef9a3c656d85",
        "Qwen3.5-4B.Q4_K_S.gguf": "64a4ae38d777e3b9c55c31ad8009b598c7fbfd0cc94c863f0be0f4aca2b91e80",
        "Qwen3.5-4B.Q5_K_M.gguf": "55863d344ed1e03e6d78f6782340a9de9d6a3c23af5ea0b881743776acc35a68",
        "Qwen3.5-4B.Q5_K_S.gguf": "ac56a742891701b0b6489d17e9b1105ab96ef80999c426a9747ae1c2c1c12774",
        "Qwen3.5-4B.Q6_K.gguf": "298cae8e619fcc323e63084a27bd1bc6d82e106e32d530e0dafaea5e12420604",
        "Qwen3.5-4B.Q8_0.gguf": "a5442a83decb48747835cf0cb7c219432ac655f6dc1a805fb0301d029d91fbd5",
        "mmproj-BF16.gguf": "5ce63ce0113f4bb7b87dc19d076fe0f951c94d4e593154c7a84f605b2f57d423",
    },
    "qwythos-9b-v2-compact": {
        "empero-ai_Qwythos-9B-v2-IQ2_M.gguf": "b68e5df7b7f623dce05ed4ddf67786e2a89f4843fa711f350119dffb8ea18076",
        "empero-ai_Qwythos-9B-v2-IQ3_M.gguf": "89bfcd852a63d46aa5f7ca5d4b9fe49489762a77addfb15b8f951ce0ebaa2848",
        "empero-ai_Qwythos-9B-v2-IQ3_XS.gguf": "83bcd7b528747cbda08f4b9da66634ebb438adc3a87d61a9021243bb9ed06225",
        "empero-ai_Qwythos-9B-v2-IQ3_XXS.gguf": "c1234dbfe66756ebee3952dfb47e070c324adb4f3e180324d9b18aad225536cc",
        "empero-ai_Qwythos-9B-v2-IQ4_XS.gguf": "f1663b67277149898804732265b443becaa3b8519df513e4391474724ca7b45e",
        "empero-ai_Qwythos-9B-v2-Q2_K.gguf": "059cf006853e145e2386c626afc11023cae16344d6d1d243268ae0d6de768f91",
        "empero-ai_Qwythos-9B-v2-Q2_K_L.gguf": "193209b07ae057bdb635f2b93495cae0cb173d0b66fc04412c138e3d6dee0acf",
        "empero-ai_Qwythos-9B-v2-Q3_K_L.gguf": "2de340253070c18db6e778a3ee3adaea4e17660719d4f73b188712199b408406",
        "empero-ai_Qwythos-9B-v2-Q3_K_M.gguf": "5ce4b1e97d868de896e7c2331d4fa645bcfb782fce4ecf0b75c6f52df27a1c70",
        "empero-ai_Qwythos-9B-v2-Q3_K_S.gguf": "6c4d21b8424b63ccc3da1c7bd6de92794e21f99de1d545693b84608cc3bf8db8",
    },
}

MMPROJ = {
    # phi-4-mini-3.8b deliberately absent: Phi-4-mini-instruct is text-only.
    "qwen3.5-4b": ("mmproj-BF16.gguf", 675569344),
    "qwen3.5-2b": ("mmproj-BF16.gguf", 671372992),
    # qwen3.5-4b-opus-4.6-distill: the repo ships mmproj-BF16.gguf, but the card
    # makes no vision claim, so it is not listed and not downloaded.
    # bartowski ships no projector. The vision tower is untouched by the
    # Qwythos fine-tune, so empero's projector for the same weights is used,
    # served from empero's repo (the optional third field).
    "qwythos-9b-v2-compact": ("mmproj-Qwythos-9B-v2-BF16.gguf", 921704512, "empero-ai/Qwythos-9B-v2-GGUF"),
    # The Gemma 4 projectors also carry an audio encoder (clip.has_audio_encoder);
    # the app only feeds them images.
    "gemma-4-e4b": ("mmproj-BF16.gguf", 991552320),
    "gemma-4-e2b": ("mmproj-BF16.gguf", 986833728),
}

EXTRA_FILES = {}


def sha_for(mid, fname):
    """Per-model checksum first, then the flat table; None when neither has it."""
    return SHA256_BY_MODEL.get(mid, {}).get(fname) or SHA256.get(fname)


def build():
    models = []

    models.append({
        "id": "phi-4-mini-3.8b",
        "displayName": "Phi-4-mini-instruct",
        "family": "Microsoft Phi",
        "parameterCount": "3.8B",
        "sizeClass": "3.8B",
        "blurb": "Compact 3.8B instruction model with a 128K window. The lightest text-only entry in the catalogue - even its largest quant loads comfortably on an 8 GB device.",
        "hfModelId": "microsoft/Phi-4-mini-instruct",
        "hfModelSha": "cfbefacb99257ffa30c83adab238a50856ac3083",
        "hfModelLastModified": "2025-12-10T20:24:40.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "The official repo ships safetensors only (2 shards, 3,836,021,760 parameters). The GGUF listed here is bartowski's imatrix conversion. Note the repository id: bartowski publishes it as bartowski/microsoft_Phi-4-mini-instruct-GGUF, prefixing the upstream org with an underscore. `bartowski/Phi-4-mini-instruct-GGUF` does not exist and returns 404.",
        "visionSupported": False,
        "visionEvidence": None,
        "visionAbsenceNote": "Confirmed text-only. pipeline_tag is text-generation and the repo carries no vision, image-to-text or multimodal tag; there is no preprocessor_config.json and the GGUF repository ships no mmproj-*.gguf. OCR mode must refuse this model.",
        "recommendedContextLength": 8192,
        "maxContextLength": 131072,
        "contextNote": "131,072 tokens (128K), taken from the GGUF's own metadata (architecture phi3, context_length 131072) - that is the value the loader will honour. 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 3.4,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20},
        "notes": "The upstream card samples greedily in its own examples (do_sample=False, temperature 0.0) and neither it nor generation_config.json documents a sampler, so the values here are this app's house defaults - chosen so answers do not degenerate into repetition, and adjustable in Settings. Every one of the 23 published quants fits this device. The card cautions that a 3.8B model cannot hold much factual knowledge and suggests retrieval augmentation for fact-heavy questions.",
    })

    # The four entries below were added for a device with 4-5 GB free at load
    # time rather than the 9 GB the targetDevice block assumes. Their
    # ramRequirementGb is the recommended quant's weights plus KV cache and
    # compute buffers at 8192 context, and EXCLUDES the projector: the load
    # preflight adds mmproj.sizeBytes itself when vision is in use. Qwen3.5 is a
    # hybrid model with attention on one layer in four, so its KV cache is a
    # fraction of a dense model's; 0.5-0.6 GB is a deliberately rounded-up figure.

    models.append({
        "id": "qwythos-9b-v2-compact",
        "displayName": "Qwythos-9B-v2 (compact quants)",
        "family": "Empero AI",
        "parameterCount": "9B",
        "sizeClass": "9B",
        "blurb": "The same Qwythos-9B-v2 weights in 2-4 bit quants that empero does not publish, for phones with less free RAM.",
        "hfModelId": "empero-ai/Qwythos-9B-v2",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": True,
        "hfModelFileNote": "empero's own GGUF repo stops at Q4_K_M (5.74 GB). These quants are bartowski's imatrix conversion of the same model. bartowski's files run larger than empero's at the same label (Q4_K_M is 6.05 GB here), so only the quants smaller than empero's smallest are listed.",
        "visionSupported": True,
        "visionEvidence": "Same weights as qwythos-9b-v2, whose card has a dedicated 'Vision (image input)' section. bartowski's repo ships no projector, so empero's mmproj-Qwythos-9B-v2-BF16.gguf is used, downloaded from empero's repo.",
        "visionCaveat": "The projector comes from a different repository than the weights. It matches the same model, but this pairing has not been tested on-device, and very low-bit quants degrade image reasoning further. Training was text-only; the vision tower was never fine-tuned.",
        "recommendedContextLength": 8192,
        "maxContextLength": 1048576,
        "contextNote": "Same YaRN 1M window as qwythos-9b-v2. Lower the in-app value to save KV-cache memory.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 5.0,
        "warning": None,
        "recommendedQuant": "IQ3_XXS",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20, "repeatPenalty": 1.05},
        "notes": "At 2-3 bits a 9B model loses noticeable quality; the 4B entries are often the better trade on a tight budget. The update checker polls bartowski's repo only, so a change to empero's projector is not detected.",
    })

    models.append({
        "id": "qwen3.5-4b",
        "displayName": "Qwen3.5-4B",
        "family": "Qwen",
        "parameterCount": "4B",
        "sizeClass": "4B",
        "blurb": "Official 4B Qwen3.5 with image input. The same architecture as Qwythos at under half the RAM.",
        "hfModelId": "Qwen/Qwen3.5-4B",
        "hfModelSha": "851bf6e806efd8d0a36b00ddf55e13ccb7b8cd0a",
        "hfModelLastModified": "2026-03-02T00:52:52.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "The official repo ships safetensors only. The GGUF listed here is unsloth's conversion, which includes Unsloth Dynamic (UD-) quants and the vision projector.",
        "visionSupported": True,
        "visionEvidence": "pipeline_tag=image-text-to-text on both Qwen/Qwen3.5-4B and the GGUF repo; GGUF repo ships mmproj-BF16.gguf.",
        "recommendedContextLength": 8192,
        "maxContextLength": 262144,
        "contextNote": "262,144 natively. 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 3.3,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20},
        "notes": "Thinks inside <think>...</think> by default. Sampling is the card's 'precise' thinking preset; the card's general preset (temperature 1.0, presence_penalty 1.5) needs a presence penalty this engine does not expose.",
    })

    models.append({
        "id": "qwen3.5-4b-opus-4.6-distill",
        "displayName": "Qwen3.5-4B-Claude-Opus-4.6-Distill",
        "family": "Jackrong",
        "parameterCount": "4B",
        "sizeClass": "4B",
        "blurb": "Text-only reasoning distil of Qwen3.5-4B on Claude Opus 4.6 traces. The closest small sibling to Qwythos.",
        "hfModelId": "Jackrong/Qwen3.5-4B-Claude-4.6-Opus-Reasoning-Distilled-GGUF",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": True,
        "hfModelFileNote": "File names start with plain 'Qwen3.5-4B.' rather than the distil's name; they are the real repository paths.",
        "visionSupported": False,
        "visionEvidence": None,
        "visionAbsenceNote": "Treated as text-only. The repo does ship mmproj-BF16.gguf, but pipeline_tag is text-generation, there is no vision tag, and the card makes no vision claim, so the projector is neither listed nor downloaded. OCR mode must refuse this model.",
        "recommendedContextLength": 8192,
        "maxContextLength": 16384,
        "contextNote": "The card states fine-tuning used a 16,384-token window.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 3.3,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20},
        "notes": "Emits reasoning inside <think>...</think> tags. The card reports evaluation at temperature 0 and documents no sampler, so these are the app's Qwen3.5 defaults.",
    })

    models.append({
        "id": "qwen3.5-2b",
        "displayName": "Qwen3.5-2B",
        "family": "Qwen",
        "parameterCount": "2B",
        "sizeClass": "2B",
        "blurb": "Official 2B Qwen3.5 with image input. The lightest vision model here; loads with room to spare.",
        "hfModelId": "Qwen/Qwen3.5-2B",
        "hfModelSha": "15852e8c16360a2fea060d615a32b45270f8a8fc",
        "hfModelLastModified": "2026-03-02T11:26:29.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "The official repo ships safetensors only. The GGUF listed here is unsloth's conversion, which includes the vision projector.",
        "visionSupported": True,
        "visionEvidence": "pipeline_tag=image-text-to-text on both Qwen/Qwen3.5-2B and the GGUF repo; GGUF repo ships mmproj-BF16.gguf.",
        "recommendedContextLength": 8192,
        "maxContextLength": 262144,
        "contextNote": "262,144 natively. 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 1.8,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20},
        "notes": "A 2B model holds little factual knowledge; best for OCR, short explanations and quick questions. The projector (0.67 GB) is about half the size of the recommended weights.",
    })

    # Gemma 4 E-models keep a per-layer embedding (PLE) table in the file: 1.60 GB
    # of E4B's 4.22 GB and 1.33 GB of E2B's 2.62 GB, summed from the GGUF tensor
    # table. llama.cpp memory-maps it and reads one row per token, so most of it
    # never becomes resident. ramRequirementGb still counts the whole file: the
    # preflight compares against MemAvailable, and over-asking is recoverable
    # where a native OOM is not. Gemma 4's sliding-window layers keep the KV cache
    # small; 0.5-0.6 GB covers it plus compute buffers at 8192 context.

    models.append({
        "id": "gemma-4-e4b",
        "displayName": "Gemma 4 E4B",
        "family": "Google Gemma",
        "parameterCount": "E4B",
        "sizeClass": "4B",
        "blurb": "Google's on-device Gemma 4 with image input. Quantisation-aware trained, so the 4-bit file stays close to full quality.",
        "hfModelId": "google/gemma-4-E4B-it",
        "hfModelSha": "ee0ef6023621cff504d758262d4e04895a5af4a2",
        "hfModelLastModified": "2026-07-20T16:42:03.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "The instruction-tuned repo ships safetensors. Google also publishes a single-file QAT Q4_0 GGUF (5.15 GB); unsloth's QAT build listed here is smaller (UD-Q4_K_XL, 4.22 GB) from the same QAT checkpoint.",
        "visionSupported": True,
        "visionEvidence": "Google's card lists Text, Image and Audio input for E4B; the GGUF repo ships mmproj-BF16.gguf whose header declares clip.projector_type=gemma4v with a vision encoder.",
        "recommendedContextLength": 8192,
        "maxContextLength": 131072,
        "contextNote": "128K natively (gemma4.context_length=131072 in the GGUF). 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 4.8,
        "warning": None,
        "recommendedQuant": "UD-Q4_K_XL",
        "samplingDefaults": {"temperature": 1.0, "topP": 0.95, "topK": 64},
        "notes": "Sampling is the card's standard configuration for all use cases. 'E4B' means about 4B effective parameters; the file is larger because of the per-layer embedding table, most of which stays on storage. The projector also includes an audio encoder the app does not use.",
    })

    models.append({
        "id": "gemma-4-e2b",
        "displayName": "Gemma 4 E2B",
        "family": "Google Gemma",
        "parameterCount": "E2B",
        "sizeClass": "2B",
        "blurb": "The smallest Gemma 4, with image input. Quantisation-aware trained; fits comfortably with room to spare.",
        "hfModelId": "google/gemma-4-E2B-it",
        "hfModelSha": "3e22461f65e89153144f8adb70e3b8c2cc9845a7",
        "hfModelLastModified": "2026-07-20T16:41:56.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "The instruction-tuned repo ships safetensors. Google also publishes a single-file QAT Q4_0 GGUF (3.35 GB); unsloth's QAT build listed here is smaller (UD-Q4_K_XL, 2.62 GB) from the same QAT checkpoint.",
        "visionSupported": True,
        "visionEvidence": "Google's card lists Text, Image and Audio input for E2B; the GGUF repo ships mmproj-BF16.gguf whose header declares clip.projector_type=gemma4v with a vision encoder.",
        "recommendedContextLength": 8192,
        "maxContextLength": 131072,
        "contextNote": "128K natively (gemma4.context_length=131072 in the GGUF). 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 3.1,
        "warning": None,
        "recommendedQuant": "UD-Q4_K_XL",
        "samplingDefaults": {"temperature": 1.0, "topP": 0.95, "topK": 64},
        "notes": "Sampling is the card's standard configuration for all use cases. The projector (0.99 GB) is large next to the weights; text-only chats do not load it.",
    })

    for m in models:
        mid = m["id"]
        meta = REPOS[mid]
        repo = meta["repo"]
        m["ggufRepoId"] = repo
        m["ggufRepoSha"] = meta["sha"]
        m["ggufRepoLastModified"] = meta["last_modified"]
        m["ggufRepoUrl"] = f"https://huggingface.co/{repo}"
        m["downloadUrlPattern"] = f"https://huggingface.co/{repo}/resolve/main/{{fileName}}"

        quants = []
        for fname, label, size, note, fits in QUANTS[mid]:
            sha = sha_for(mid, fname)
            if sha is None:
                raise SystemExit(f"no SHA-256 recorded for {fname}")
            quants.append({
                "quant": label,
                "fileName": fname,
                "sizeBytes": size,
                "sizeGb": round(size / 1e9, 2),
                "sha256": sha,
                "qualityNote": note,
                "fitsTargetDevice": fits,
                "downloadUrl": RESOLVE.format(repo=repo, fname=fname),
            })
        m["quants"] = quants

        if mid in MMPROJ:
            fname, size, *source = MMPROJ[mid]
            mmproj_repo = source[0] if source else repo
            sha = sha_for(mid, fname)
            if sha is None:
                raise SystemExit(f"no SHA-256 recorded for {fname}")
            m["mmproj"] = {
                "fileName": fname,
                "sizeBytes": size,
                "sizeGb": round(size / 1e9, 2),
                "sha256": sha,
                "downloadUrl": RESOLVE.format(repo=mmproj_repo, fname=fname),
            }
        else:
            m["mmproj"] = None

        extras = EXTRA_FILES.get(mid)
        m["extraFiles"] = [
            {
                "fileName": f,
                "sizeBytes": s,
                "downloadUrl": RESOLVE.format(repo=repo, fname=f),
            }
            for f, s in (extras or [])
        ]

        rec = m["recommendedQuant"]
        match = [q for q in quants if q["quant"] == rec]
        if not match:
            raise SystemExit(f"recommended quant {rec} missing from {mid}")
        m["recommendedQuantInfo"] = match[0]

    doc = {
        "schemaVersion": 1,
        "generatedAt": "2026-09-24",
        "sourceOfTruth": "tool/generate_models_catalogue.py",
        "researchBrief": "docs/PHASE1_RESEARCH_BRIEF.md",
        "notes": [
            "Every sizeBytes value is an exact byte count from the HuggingFace file tree API, not an estimate.",
            "Version baselines (ggufRepoSha / ggufRepoLastModified) drive the auto-update checker.",
            "visionSupported is true only where the model card confirms it. Nothing here is assumed.",
            "Every model targets a phone with 4-5 GB free at load time. ramRequirementGb excludes the projector; the load preflight adds it when vision is used.",
            "2026-10-03: the 27B, MiMo 9B and the three empero 9B Q4+ entries were removed as too large for that budget; Gemma 4 E4B/E2B were added.",
        ],
        "targetDevice": {
            "name": "Samsung Galaxy S25",
            "os": "Android 15",
            "chipsets": "Snapdragon 8 Elite",
            "ramOptionsGb": [8, 12],
            "usableRamGb": 9,
        },
        "models": models,
    }

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models_catalogue.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=True)
        fh.write("\n")

    total = sum(len(m["quants"]) for m in models)
    print(f"wrote {out}: {len(models)} models, {total} quant entries")


if __name__ == "__main__":
    build()
