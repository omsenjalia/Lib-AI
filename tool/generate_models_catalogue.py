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
    "qwen3.8-27b": dict(
        repo="unsloth/Qwen3.8-27B-GGUF",
        sha="4ca720788d1e01f1bff70c033e0d0028fd02e502",
        last_modified="2026-08-20T12:04:25.000Z",
        likes=4564,
        downloads=7134167,
    ),
    "mimo-v2.6-9b": dict(
        repo="bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF",
        sha="4371da10c84fb26da3592d4cf312d24aa82b7b65",
        last_modified="2026-09-21T22:44:19.000Z",
        likes=36,
        downloads=27091,
    ),
    "qwythos-9b-v2": dict(
        repo="empero-ai/Qwythos-9B-v2-GGUF",
        sha="97c11b03687f194b300efbdb4760d9bc4021b759",
        last_modified="2026-07-12T00:58:46.000Z",
        likes=0,
        downloads=0,
    ),
    "qwythos-9b-mythos-5-1m": dict(
        repo="empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF",
        sha="5cebd89dd078b033c26988248740ddadf40f2fbd",
        last_modified="2026-07-14T13:12:53.000Z",
        likes=0,
        downloads=0,
    ),
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
    "qwen3.5-9b-opus-4.6-distill": dict(
        repo="empero-ai/Qwen3.5-9B-Claude-Opus-4.6-Distill-GGUF",
        sha="892a4362ba5896d67d566a316973fefb70f5135f",
        last_modified="2026-03-15T23:23:35.000Z",
        likes=0,
        downloads=0,
    ),
}

# (file_name, quant_label, size_bytes, quality_note[, fits_9gb])
QUANTS = {
    "qwen3.8-27b": [
        ("Qwen3.8-27B-UD-IQ1_S.gguf", "UD-IQ1_S", 6192222208, "Emergency quant. Severe quality loss on a 27B.", True),
        ("Qwen3.8-27B-UD-IQ1_M.gguf", "UD-IQ1_M", 6729166848, "Emergency quant. Severe quality loss on a 27B.", True),
        ("Qwen3.8-27B-UD-IQ2_XXS.gguf", "UD-IQ2_XXS", 7266070528, "Smallest plausible load. Quality is poor but coherent.", True),
        ("Qwen3.8-27B-UD-IQ2_S.gguf", "UD-IQ2_S", 8371970048, "Over budget once KV cache is counted.", False),
        ("Qwen3.8-27B-UD-Q2_K_XL.gguf", "UD-Q2_K_XL", 9828981664, "Exceeds usable RAM on an 8 GB device.", False),
        ("Qwen3.8-27B-UD-IQ3_XXS.gguf", "UD-IQ3_XXS", 10934860704, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-IQ3_S.gguf", "UD-IQ3_S", 12040883104, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q3_K_XL.gguf", "UD-Q3_K_XL", 13146393504, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-IQ4_XS.gguf", "UD-IQ4_XS", 14252845984, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q4_K_S.gguf", "UD-Q4_K_S", 15358213024, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-Q4_0.gguf", "Q4_0", 16056478688, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q4_K_M.gguf", "UD-Q4_K_M", 16464440224, "The quant the brief assumed would fit. It does not.", False),
        ("Qwen3.8-27B-Q4_1.gguf", "Q4_1", 17540705248, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q4_K_XL.gguf", "UD-Q4_K_XL", 17559178144, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q5_K_S.gguf", "UD-Q5_K_S", 18665753504, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q5_K_M.gguf", "UD-Q5_K_M", 19771509664, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q5_K_XL.gguf", "UD-Q5_K_XL", 20876938144, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q6_K.gguf", "UD-Q6_K", 21983677344, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q6_K_M.gguf", "UD-Q6_K_M", 23088409504, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q6_K_L.gguf", "UD-Q6_K_L", 24193919904, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q6_K_XL.gguf", "UD-Q6_K_XL", 25299061664, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q8_K_L.gguf", "UD-Q8_K_L", 28045695904, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-Q8_0.gguf", "Q8_0", 29047086048, "Exceeds usable RAM.", False),
        ("Qwen3.8-27B-UD-Q8_K_XL.gguf", "UD-Q8_K_XL", 31457991680, "Exceeds usable RAM.", False),
    ],
    "mimo-v2.6-9b": [
        ("MiMo-V2.6-Distill-Qwen-9B-Q2_K.gguf", "Q2_K", 3644380704, "Smallest. Noticeable quality loss.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-IQ3_XXS.gguf", "IQ3_XXS", 4138833440, "Very low bit. Usable for testing only.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q3_K_S.gguf", "Q3_K_S", 4260304416, "Low quality but workable.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-IQ3_XS.gguf", "IQ3_XS", 4268037664, "Low quality but workable.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q3_K_M.gguf", "Q3_K_M", 4479948320, "Reasonable compromise if RAM is tight.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q3_K_L.gguf", "Q3_K_L", 4659156512, "Reasonable compromise if RAM is tight.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-IQ3_M.gguf", "IQ3_M", 4846458400, "Reasonable compromise if RAM is tight.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-IQ4_XS.gguf", "IQ4_XS", 5227304480, "Good quality/size balance.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q4_0.gguf", "Q4_0", 5482829344, "Legacy 4-bit. Prefer Q4_K_M.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q4_K_S.gguf", "Q4_K_S", 5483255328, "Good quality/size balance.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-IQ4_NL.gguf", "IQ4_NL", 5825058336, "Very close to Q4_K_M in quality.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf", "Q4_K_M", 5841049120, "RECOMMENDED. Best balance for this device.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q4_K_L.gguf", "Q4_K_L", 6202021408, "Slightly better than Q4_K_M, slightly larger.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q5_K_S.gguf", "Q5_K_S", 6496015904, "Higher fidelity, more RAM.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q5_K_M.gguf", "Q5_K_M", 6876124704, "Higher fidelity, more RAM.", True),
        ("MiMo-V2.6-Distill-Qwen-9B-Q6_K_S.gguf", "Q6_K_S", 7509284384, "Getting tight for an 8 GB device.", False),
        ("MiMo-V2.6-Distill-Qwen-9B-Q6_K.gguf", "Q6_K", 7793710624, "Getting tight for an 8 GB device.", False),
        ("MiMo-V2.6-Distill-Qwen-9B-Q6_K_L.gguf", "Q6_K_L", 8106579488, "Getting tight for an 8 GB device.", False),
        ("MiMo-V2.6-Distill-Qwen-9B-Q8_0.gguf", "Q8_0", 9545979424, "Near-lossless. Too large for comfortable load.", False),
        ("MiMo-V2.6-Distill-Qwen-9B-bf16.gguf", "BF16", 17920693440, "Full precision. Not loadable on this device.", False),
    ],
    "qwythos-9b-v2": [
        ("Qwythos-9B-v2-Q4_K_M.gguf", "Q4_K_M", 5736063744, "RECOMMENDED. Model author's stated default.", True),
        ("Qwythos-9B-v2-Q5_K_M.gguf", "Q5_K_M", 6523806464, "Balanced quality/size.", True),
        ("Qwythos-9B-v2-Q6_K.gguf", "Q6_K", 7458300672, "High quality. Tight but feasible.", True),
        ("Qwythos-9B-v2-Q8_0.gguf", "Q8_0", 9527501568, "Near-lossless. Too large for comfortable load.", False),
        ("Qwythos-9B-v2-BF16.gguf", "BF16", 17920697088, "Full precision. Not loadable on this device.", False),
        ("Qwythos-9B-v2-MTP-Q4_K_M.gguf", "Q4_K_M (MTP)", 5903822528, "Multi-token-prediction head. Needs newer llama.cpp.", True),
        ("Qwythos-9B-v2-MTP-Q5_K_M.gguf", "Q5_K_M (MTP)", 6710963904, "MTP variant.", True),
        ("Qwythos-9B-v2-MTP-Q6_K.gguf", "Q6_K (MTP)", 7666069184, "MTP variant.", False),
        ("Qwythos-9B-v2-MTP-Q8_0.gguf", "Q8_0 (MTP)", 9786060480, "MTP variant.", False),
        ("Qwythos-9B-v2-MTP-BF16.gguf", "BF16 (MTP)", 18407321280, "MTP full precision.", False),
    ],
    "qwythos-9b-mythos-5-1m": [
        ("Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf", "Q4_K_M", 5629108896, "RECOMMENDED. Model author's stated default.", True),
        ("Qwythos-9B-Claude-Mythos-5-1M-Q5_K_M.gguf", "Q5_K_M", 6467969696, "Balanced quality/size.", True),
        ("Qwythos-9B-Claude-Mythos-5-1M-Q6_K.gguf", "Q6_K", 7359259296, "High quality. Tight but feasible.", True),
        ("Qwythos-9B-Claude-Mythos-5-1M-Q8_0.gguf", "Q8_0", 9527501472, "Near-lossless. Too large for comfortable load.", False),
        ("Qwythos-9B-Claude-Mythos-5-1M-BF16.gguf", "BF16", 17920696992, "Full precision. Not loadable on this device.", False),
        ("Qwythos-9B-Claude-Mythos-5-1M-MTP-Q4_K_M.gguf", "Q4_K_M (MTP)", 5887667808, "MTP variant.", True),
        ("Qwythos-9B-Claude-Mythos-5-1M-MTP-Q5_K_M.gguf", "Q5_K_M (MTP)", 6726528608, "MTP variant.", True),
        ("Qwythos-9B-Claude-Mythos-5-1M-MTP-Q6_K.gguf", "Q6_K (MTP)", 7617818208, "MTP variant.", False),
        ("Qwythos-9B-Claude-Mythos-5-1M-MTP-Q8_0.gguf", "Q8_0 (MTP)", 9786060384, "MTP variant.", False),
        ("Qwythos-9B-Claude-Mythos-5-1M-MTP-BF16.gguf", "BF16 (MTP)", 18407321184, "MTP full precision.", False),
    ],
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
    "qwen3.5-9b-opus-4.6-distill": [
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q2_K.gguf", "Q2_K", 3827261760, "Smallest. Noticeable quality loss.", True),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q3_K_M.gguf", "Q3_K_M", 4623524160, "Low quality but workable.", True),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q4_K_M.gguf", "Q4_K_M", 5629108544, "RECOMMENDED. Best balance for this device.", True),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q5_K_M.gguf", "Q5_K_M", 6467969344, "Higher fidelity, more RAM.", True),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q6_K.gguf", "Q6_K", 7359258944, "High quality. Tight but feasible.", True),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-Q8_0.gguf", "Q8_0", 9527501120, "Near-lossless. Too large for comfortable load.", False),
        ("Qwen3.5-9B-Claude-Opus-4.6-Distill-f16.gguf", "F16", 17920696640, "Full precision. Not loadable on this device.", False),
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
    # unsloth/Qwen3.8-27B-GGUF
    "Qwen3.8-27B-UD-IQ1_S.gguf": "3895b6eaa91e705c06ad1938d16c22e86f073c6a67df86260a1da79be3d1f887",
    "Qwen3.8-27B-UD-IQ1_M.gguf": "1b5165a7149ea51e683c8eaf23372188ad9fc9d1a795386f7a1b558acf847dc6",
    "Qwen3.8-27B-UD-IQ2_XXS.gguf": "e792d8fb3142fe6d9171876d6da0f71f05a71028718debc72dbec93ff645e67d",
    "Qwen3.8-27B-UD-IQ2_S.gguf": "7897d2c5a5cee46aef50895141b2c8a0803c1185f3d03c4fda4cd137a7ad77fe",
    "Qwen3.8-27B-UD-Q2_K_XL.gguf": "fd4730dd8aad070517978752b63d530aeb1740d2283cab9fa24f1e404032ddb0",
    "Qwen3.8-27B-UD-IQ3_XXS.gguf": "c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee",
    "Qwen3.8-27B-UD-IQ3_S.gguf": "d847e2c1e4aa276e4b7b8e9ad7628050e61e165d49ab995407bc36677a6f3864",
    "Qwen3.8-27B-UD-Q3_K_XL.gguf": "8c2a45ff85e7674ca185ec8eb6cdeab0e617ed9d8018caed0b64380eb2a67a5e",
    "Qwen3.8-27B-UD-IQ4_XS.gguf": "40fac4050e940397dbf13087afd50f4734a11805bf9d65ef8ddd7483470e6199",
    "Qwen3.8-27B-UD-Q4_K_S.gguf": "75bc9c8adba2842e72f0ab5201aaa07133c5010b566305c09187fcbdcd364017",
    "Qwen3.8-27B-Q4_0.gguf": "ede16c7b36e578ca87a8c70e011e4b4633a32c831c0ce76d0f474582384e671d",
    "Qwen3.8-27B-UD-Q4_K_M.gguf": "322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482",
    "Qwen3.8-27B-Q4_1.gguf": "3e020514545c310dfc511dc8d3ddc23482b645189cb9287816d84bed6eddd4ac",
    "Qwen3.8-27B-UD-Q4_K_XL.gguf": "3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e",
    "Qwen3.8-27B-UD-Q5_K_S.gguf": "d8d62ffcf84d42658dd6ccf9782b4d0404700af78b26d750507510c7597b5bfe",
    "Qwen3.8-27B-UD-Q5_K_M.gguf": "2de73110cb254cbf09b54b717578dadff12ef1194e7271527e68202f39ba4bfd",
    "Qwen3.8-27B-UD-Q5_K_XL.gguf": "8601193d3d5760c37fb8ce1b43afebc69df5fb24e1fbc5a547c32e2200305276",
    "Qwen3.8-27B-UD-Q6_K.gguf": "c9c206812fbe4ac7b76a729e25928b63f2ae89d37f69da7a71c20aec763cd436",
    "Qwen3.8-27B-UD-Q6_K_M.gguf": "493301830a596b8ad56dc1329f80bbcb578c8e910da395feafdc9cd8263430bb",
    "Qwen3.8-27B-UD-Q6_K_L.gguf": "121355b4c7422771da25adc74090e3c90138f77ce5c92d348687d47824ec80f4",
    "Qwen3.8-27B-UD-Q6_K_XL.gguf": "85bec00cbd06ea278cd035eea4f3d62a21a54fa52b3b5cb51a12c1eb00efb19e",
    "Qwen3.8-27B-UD-Q8_K_L.gguf": "2a13bba36d2efa213f9275abc430c40e4d914b145bfde976f30f1bb5b7e23ac2",
    "Qwen3.8-27B-Q8_0.gguf": "a680f44a06920e5d689774823782006aa3acc8db95750323373b24139b67e348",
    "Qwen3.8-27B-UD-Q8_K_XL.gguf": "af36ecb6b5db1407953345b746c14ac93f0657dda413910b4348683a2d990377",
    "mmproj-BF16.gguf": "83ee4f4f205fa514161778c41df1ea14144faa0f713510893b63c2395f5c2d53",
    "mmproj-F16.gguf": "cbb841a9ee0636b2ec172f5bb8df2ea8dfeb01e90fe7c6126581d662a0b4e43e",
    # bartowski/MiMo-V2.6-Distill-Qwen-9B-GGUF
    "MiMo-V2.6-Distill-Qwen-9B-Q2_K.gguf": "1878a8f3eec5accd93ea22c46155d51c461b463ccb816cd44084ed555c81b909",
    "MiMo-V2.6-Distill-Qwen-9B-IQ3_XXS.gguf": "83d6383197adda49ed71fd6764f5d22c7993b5bc5554b5e8fd5151bc987ff04b",
    "MiMo-V2.6-Distill-Qwen-9B-Q3_K_S.gguf": "bebb948e54d473ee212eb529b5a4a47ae9645da2ae19a52bcb10ad147d09065f",
    "MiMo-V2.6-Distill-Qwen-9B-IQ3_XS.gguf": "12e213f5aab8ee66706eebc795d8c9f50acd43318538bca8411b584cad7d8132",
    "MiMo-V2.6-Distill-Qwen-9B-Q3_K_M.gguf": "d98e54ec9650b6554cfdeea531e2420009207d50471170d0c3640483df8e87eb",
    "MiMo-V2.6-Distill-Qwen-9B-Q3_K_L.gguf": "b51b85fd3bc9d060017a66ffa2d8b13ab0f743c614c06355a20bd73d03d7f627",
    "MiMo-V2.6-Distill-Qwen-9B-IQ3_M.gguf": "e2638eb0a3751b530c0b91c70292d961687d5ff993c1125a867461564d341724",
    "MiMo-V2.6-Distill-Qwen-9B-IQ4_XS.gguf": "eccfbc188e71dec8350fbdd5af898d2a50691ac67e077327c52baa9da1e91d90",
    "MiMo-V2.6-Distill-Qwen-9B-Q4_0.gguf": "0dadc6593e5fe790a510fcb7fcd1dc6993664db562b2e8ec7b34825e99d52f4f",
    "MiMo-V2.6-Distill-Qwen-9B-Q4_K_S.gguf": "db48a409bf4c11033ab4bd24ff3b1ee028578a5acc62e0b34887edbed9708253",
    "MiMo-V2.6-Distill-Qwen-9B-IQ4_NL.gguf": "9b3a443818d653af7c2a0c56aebc51668a7048ef72f8c1d77d669f544c28f6a7",
    "MiMo-V2.6-Distill-Qwen-9B-Q4_K_M.gguf": "4bca6f18c73f72270c7a20c2ea2bea581de8246e318714277120369d34048c81",
    "MiMo-V2.6-Distill-Qwen-9B-Q4_K_L.gguf": "db6b5e7b5d25525da87f4a3899555215693e8cf4ab1be9fff90ea5dee4ba957d",
    "MiMo-V2.6-Distill-Qwen-9B-Q5_K_S.gguf": "f81aa5e3e5dc6f108dd7fd37c0738976994b62929f21e2e3a3bb2ed70fb92355",
    "MiMo-V2.6-Distill-Qwen-9B-Q5_K_M.gguf": "04cf46f2b5584ef922697d6c063f94879434fb86c467f1a09e52daf0cddaf35f",
    "MiMo-V2.6-Distill-Qwen-9B-Q6_K_S.gguf": "df3b6b6be2477f280a6fa89ebb5fb455523849c20dd943b416ad43e076206f06",
    "MiMo-V2.6-Distill-Qwen-9B-Q6_K.gguf": "ef96d05a2ddf2cbb450d1af1ac3860ec769d3575bafa70692ee5609bda3fad7d",
    "MiMo-V2.6-Distill-Qwen-9B-Q6_K_L.gguf": "556d51c9f191fc06a1fd751fdb4b4082f4add0023d9ac8b7198dcecfb772cd99",
    "MiMo-V2.6-Distill-Qwen-9B-Q8_0.gguf": "2fad0aa11bb9e7aa491ff12f768954f9dd0a6e7d4ce4a897ca73ec420f3b90ae",
    "MiMo-V2.6-Distill-Qwen-9B-bf16.gguf": "5e4a50f5e41abb867585bfddd808997bc195bdd8f0df78210cd97ba406dc328e",
    "mmproj-MiMo-V2.6-Distill-Qwen-9B-bf16.gguf": "197656f5ea308d2e9e008c5c1cb239b0297d7d1c7b4c0769cee3b46c2b891714",
    "mmproj-MiMo-V2.6-Distill-Qwen-9B-f16.gguf": "ff348f3180a63188aa7285db85f550fe38acb61dd013c599eb8bad08d2cc2576",
    # empero-ai/Qwythos-9B-v2-GGUF
    "Qwythos-9B-v2-Q4_K_M.gguf": "c0a588704f422b713eca29b2c1f192ae6f69aea3f9e7cb64f9ecdb76ff7a85f4",
    "Qwythos-9B-v2-Q5_K_M.gguf": "fc5251e8e3e87d58946522833eb896c84375a715b6f89c54cdd10082ecc6ea8d",
    "Qwythos-9B-v2-Q6_K.gguf": "dd39e148823f0bab858e946d603e4bf424240aae34435580be820f09c75ca379",
    "Qwythos-9B-v2-Q8_0.gguf": "3324ac1a7260fbb484d10373df7d54d156ff6c4f5c577d87dbd0218928beab89",
    "Qwythos-9B-v2-BF16.gguf": "663e4694583caf7b3e5bdeb76c27aebb7ea86bcc2760419fea82e51e2d8087c7",
    "Qwythos-9B-v2-MTP-Q4_K_M.gguf": "cfdd00ac1c1dc9ced33f23817fb4282f2594067e02e34d82e3e63bc0ea275b05",
    "Qwythos-9B-v2-MTP-Q5_K_M.gguf": "d8ea0d2289793401a6ec546e713c885fba9e27d14cd70a36c570f975e383e659",
    "Qwythos-9B-v2-MTP-Q6_K.gguf": "24271fb6e16b2b8f581d192cf77d947453d7852f965ce6801fefa6964bbea060",
    "Qwythos-9B-v2-MTP-Q8_0.gguf": "6d72e896721f2be249b2584fb06a007a8f8ce506e592ea54c103952303a5f11f",
    "Qwythos-9B-v2-MTP-BF16.gguf": "2c46b135e2fef3c4d4b2a0e98394ae5ac5cdec54b1a5451c74ea568fbafb6075",
    "mmproj-Qwythos-9B-v2-BF16.gguf": "0d1687cb33124c78acab788b342d4a2eaf85b3035e87c3abe4ee9d0b84ddb4f5",
    # empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF
    "Qwythos-9B-Claude-Mythos-5-1M-Q4_K_M.gguf": "5c09e7f207d2fd9069c802ff77632fa7cdaffe7fb5ba40ff9f060aaeaa09acd5",
    "Qwythos-9B-Claude-Mythos-5-1M-Q5_K_M.gguf": "20013a03b23d4b5c0608cb57c489778ef7dd5fd80ee750b93c8a08f03293aab7",
    "Qwythos-9B-Claude-Mythos-5-1M-Q6_K.gguf": "2bef47eee2e83fa5e2ac5619102d8418144147be1270870aba42b22a606831e6",
    "Qwythos-9B-Claude-Mythos-5-1M-Q8_0.gguf": "e8118b9cde68a1a1dc3299060e9af7d8640c47e670e83ecd4204f15326938b70",
    "Qwythos-9B-Claude-Mythos-5-1M-BF16.gguf": "8a1d1d5dbc6bf921222d33dee2003fc98e1185f83aba54cce50acb5c278df1cb",
    "Qwythos-9B-Claude-Mythos-5-1M-MTP-Q4_K_M.gguf": "318caed45110f5e3c60bff1142e0d1e658e046e670830d9be643df33940f4f98",
    "Qwythos-9B-Claude-Mythos-5-1M-MTP-Q5_K_M.gguf": "a21b7f12f9908dbfbaeb2ad8ddd51c936ecadc780796abd70a8e5b08cdc6cd8e",
    "Qwythos-9B-Claude-Mythos-5-1M-MTP-Q6_K.gguf": "b6ca7dc848d9857c7759d7da6da502d1cb8941b69471375d74c7a539ddc381e9",
    "Qwythos-9B-Claude-Mythos-5-1M-MTP-Q8_0.gguf": "9a8f04df5b8b8af60a16ade370c9bd1a14d82e980e6d45946a0eb9282c019513",
    "Qwythos-9B-Claude-Mythos-5-1M-MTP-BF16.gguf": "f188232e7e19f38f32c0fc2dfd57c801bd0ff1e32e7a30402885ae83741aeeb3",
    "mmproj-Qwythos-9B-Claude-Mythos-5-1M-F16.gguf": "f977efc337a2ac2ba183eea0c73e25b75fc240d56c05ed4d9b56ab451f64c82c",
    # empero-ai/Qwen3.5-9B-Claude-Opus-4.6-Distill-GGUF
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q2_K.gguf": "02e0ebbd94ef6e286695ac7f0c16358810f08b677576d0b25fddf177ae78ab01",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q3_K_M.gguf": "c42e7c5ca93a34c8a95f5fd784a93b48f922e633f0de78f06966b0b3bb3ac63e",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q4_K_M.gguf": "db8793fad2be4a47521ab93030bc7846262fb7e38dd84b386c61f772d8299493",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q5_K_M.gguf": "93b3b3608e672aa6d03d09e6075ff5826d18fa188f99eb6de2869bb4193fd2d2",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q6_K.gguf": "bb44c32d77a3f7846afa523a20306efc5d7cb68781e187f87cf93a3e5994cbc9",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-Q8_0.gguf": "9ff5de17a0c98581c828c259e0beea9c9dca881b0371f61c974f59c125b08b27",
    "Qwen3.5-9B-Claude-Opus-4.6-Distill-f16.gguf": "37a8dc8761689e17ab46787274a3b5827c1e63e9767d494c015c954dbedab66b",
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

MMPROJ = {
    "qwen3.8-27b": ("mmproj-BF16.gguf", 931146432),
    "mimo-v2.6-9b": ("mmproj-MiMo-V2.6-Distill-Qwen-9B-bf16.gguf", 921704992),
    "qwythos-9b-v2": ("mmproj-Qwythos-9B-v2-BF16.gguf", 921704512),
    "qwythos-9b-mythos-5-1m": ("mmproj-Qwythos-9B-Claude-Mythos-5-1M-F16.gguf", 918165472),
    # qwen3.5-9b-opus-4.6-distill deliberately absent: no mmproj exists in that repo.
    # phi-4-mini-3.8b likewise absent: Phi-4-mini-instruct is text-only.
}

EXTRA_FILES = {
    "qwythos-9b-v2": [("SHA256SUMS", 1025)],
    "qwythos-9b-mythos-5-1m": [("SHA256SUMS", 1312), ("TEST_REPORT.md", 3721)],
}


def build():
    models = []

    models.append({
        "id": "qwen3.8-27b",
        "displayName": "Qwen3.8-27B",
        "family": "Qwen",
        "parameterCount": "27B",
        "sizeClass": "27B",
        "blurb": "Flagship 27B hybrid-attention multimodal model. Listed for completeness only.",
        "hfModelId": "Qwen/Qwen3.8-27B",
        "hfModelSha": "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0",
        "hfModelLastModified": "2026-08-14T15:00:01.000Z",
        "hfModelHasGguf": False,
        "hfModelFileNote": "Official repo ships safetensors only (18 shards, ~55 GB). No GGUF is published upstream; the quantisations below come from the third-party GGUF repo recorded in ggufRepoId.",
        "visionSupported": True,
        "visionEvidence": "pipeline_tag=image-text-to-text; architecture Qwen3_5ForConditionalGeneration; model card documents image and video input; preprocessor_config.json and video_preprocessor_config.json present; GGUF repo ships mmproj-BF16.gguf.",
        "recommendedContextLength": 8192,
        "maxContextLength": 262144,
        "contextNote": "262,144 natively. Keep the in-app value at 8192 - KV cache at 27B is expensive.",
        "wifiOnly": True,
        "highRam": True,
        "fitsTargetDevice": False,
        "ramRequirementGb": 9.2,
        "warning": "WILL NOT LOAD on a Samsung Galaxy S25. Even the smallest available quant (UD-IQ2_XXS, 7.27 GB) exceeds usable RAM once the KV cache and the 0.93 GB vision projector are counted. Every quant above IQ2_XXS is 9.8 GB or larger. Downloading this model will consume storage and is expected to fail at load time.",
        "recommendedQuant": "UD-IQ2_XXS",
        "samplingDefaults": {"temperature": 0.7, "topP": 0.95, "topK": 20},
        "notes": "No Q3_K_S and no plain Q2_K exist in this repository. The nearest larger quants are UD-Q2_K_XL (9.83 GB) and UD-Q3_K_XL (13.15 GB).",
    })

    models.append({
        "id": "mimo-v2.6-9b",
        "displayName": "MiMo-V2.6-Distill-Qwen-9B",
        "family": "Xiaomi MiMo",
        "parameterCount": "9B",
        "sizeClass": "9B",
        "blurb": "Agentic and coding distil of Qwen3.5-9B, SFT'd by Xiaomi on MiMo-generated data.",
        "hfModelId": "XiaomiMiMo/MiMo-V2.6-Distill-Qwen-9B",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": False,
        "hfModelFileNote": "Official repo ships safetensors only (4 shards, ~18.8 GB). The GGUF listed here is bartowski's conversion; ggml-org publishes an authoritative conversion but only at Q8_0 (9.55 GB), which is too large for this device.",
        "visionSupported": True,
        "visionEvidence": "pipeline_tag=image-text-to-text; model card benchmarks a Visual coding domain; preprocessor_config.json and video_preprocessor_config.json present; GGUF repo ships mmproj-MiMo-V2.6-Distill-Qwen-9B-bf16.gguf.",
        "recommendedContextLength": 8192,
        "maxContextLength": 262144,
        "contextNote": "262,144 native. 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 7.2,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20},
        "notes": "Distilled for agentic tool use and code. Chat template is MiMo v2.6's own.",
    })

    models.append({
        "id": "qwythos-9b-v2",
        "displayName": "Qwythos-9B-v2",
        "family": "Empero AI",
        "parameterCount": "9B",
        "sizeClass": "9B",
        "blurb": "Reasoning model post-trained on Claude Mythos/Fable traces, with repetition looping trained out.",
        "hfModelId": "empero-ai/Qwythos-9B-v2-GGUF",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": True,
        "hfModelFileNote": None,
        "visionSupported": True,
        "visionEvidence": "Model card has a dedicated 'Vision (image input)' section with a worked llama-mtmd-cli example; tags include multimodal and vision; repo ships mmproj-Qwythos-9B-v2-BF16.gguf.",
        "visionCaveat": "The model card states verbatim that training was text-only and the vision tower was never fine-tuned, so image-grounded reasoning inherits base Qwen3.5-9B behaviour and has not been independently evaluated.",
        "recommendedContextLength": 8192,
        "maxContextLength": 1048576,
        "contextNote": "Ships YaRN rope-scaling for a 1,048,576-token window. 8192 recommended on-device; lower it to cut KV-cache memory.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 7.1,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20, "repeatPenalty": 1.05},
        "notes": "Hybrid Gated-DeltaNet architecture (3:1 SSM:attention). K-quants keep SSM state tensors at higher precision, so files run ~2-4% larger than a flat K-quant. Repo ships SHA256SUMS.",
    })

    models.append({
        "id": "qwythos-9b-mythos-5-1m",
        "displayName": "Qwythos-9B-Claude-Mythos-5.1M",
        "family": "Empero AI",
        "parameterCount": "9B",
        "sizeClass": "9B",
        "blurb": "Full-parameter reasoning model post-trained on 500M+ tokens of Claude Mythos/Fable traces.",
        "hfModelId": "empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": True,
        "hfModelFileNote": None,
        "visionSupported": True,
        "visionEvidence": "Model card has a full 'Vision (image input)' section including an OpenAI-compatible server example; tags include multimodal and vision; repo ships mmproj-Qwythos-9B-Claude-Mythos-5-1M-F16.gguf.",
        "visionCaveat": "Vision tower frozen from the Qwen3.5-9B base; the SFT was text-only and image reasoning has not been independently evaluated.",
        "recommendedContextLength": 8192,
        "maxContextLength": 1048576,
        "contextNote": "YaRN rope-scaling baked in for a 1,048,576-token window. 8192 recommended on-device.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 7.0,
        "warning": "Avoid greedy decoding and temperatures at or below 0.3 with this model - the model card documents repetition loops under low-temperature sampling.",
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.6, "topP": 0.95, "topK": 20, "repeatPenalty": 1.05},
        "notes": "Reported +34 pts MMLU / +30 pts gsm8k-strict over base Qwen3.5-9B. Native function calling. Repo ships SHA256SUMS and TEST_REPORT.md.",
    })

    models.append({
        "id": "qwen3.5-9b-opus-4.6-distill",
        "displayName": "Qwen3.5-9B-Claude-Opus-4.6-Distill",
        "family": "Empero AI",
        "parameterCount": "9B",
        "sizeClass": "9B",
        "blurb": "Text-only reasoning distil of Qwen3.5-9B trained on Claude Opus 4.6 reasoning traces.",
        "hfModelId": "empero-ai/Qwen3.5-9B-Claude-Opus-4.6-Distill-GGUF",
        "hfModelSha": None,
        "hfModelLastModified": None,
        "hfModelHasGguf": True,
        "hfModelFileNote": None,
        "visionSupported": False,
        "visionEvidence": None,
        "visionAbsenceNote": "Confirmed text-only. No mmproj-*.gguf exists in the repository, the card carries no vision or multimodal tag, and it makes no vision claim. OCR mode must refuse this model.",
        "recommendedContextLength": 4096,
        "maxContextLength": 4096,
        "contextNote": "SFT max sequence length was 4096. Do not raise this expecting better results.",
        "wifiOnly": False,
        "highRam": False,
        "fitsTargetDevice": True,
        "ramRequirementGb": 5.8,
        "warning": None,
        "recommendedQuant": "Q4_K_M",
        "samplingDefaults": {"temperature": 0.7, "topP": 0.95, "topK": 20},
        "notes": "Emits reasoning inside <think>...</think> tags. The repo README documents lowercase filenames that do not match the real files; the filenames here are the actual repository paths.",
    })

    models.append({
        "id": "phi-4-mini-3.8b",
        "displayName": "Phi-4-mini-instruct",
        "family": "Microsoft Phi",
        "parameterCount": "3.8B",
        "sizeClass": "3.8B",
        "blurb": "Compact 3.8B instruction model with a 128K window. The lightest entry in the catalogue - even its largest quant loads comfortably on an 8 GB device.",
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
            sha = SHA256.get(fname)
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
            fname, size = MMPROJ[mid]
            m["mmproj"] = {
                "fileName": fname,
                "sizeBytes": size,
                "sizeGb": round(size / 1e9, 2),
                "sha256": SHA256[fname],
                "downloadUrl": RESOLVE.format(repo=repo, fname=fname),
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
            "The Qwen3.8-27B entry is intentionally marked fitsTargetDevice=false; see its warning field.",
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
