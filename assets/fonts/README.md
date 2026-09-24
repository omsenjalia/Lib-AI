# Bundled typefaces

All fonts are shipped with the app; none are fetched at runtime. An offline app
that downloaded its own typeface the first time it rendered a heading would not
be offline for long.

The set below is the substitute triple for the interface this shell replicates.
The reference app sets display copy in Copernicus and its controls in Styrene B;
both are licensed and cannot be redistributed, so the documented open substitutes
are used instead — Lora for display, Lato for UI, JetBrains Mono for code.

| Family | File | Use |
|---|---|---|
| Lora | `Lora-Variable.ttf`, `Lora-Italic-Variable.ttf` | Display copy: the home greeting and section headings |
| Lato | `Lato-Regular.ttf` (400), `Lato-Italic.ttf` (400 italic), `Lato-Medium.ttf` (500), `Lato-Bold.ttf` (700) | Every control and body run |
| JetBrains Mono | `JetBrainsMono-Variable.ttf` | Code blocks, inline code, the token/maths readouts |

Lora and JetBrains Mono ship as variable files and are used at their default
instance (400); every weight the interface actually needs is one of the four Lato
files, so no variable-axis configuration is involved. Lato's other weights
(100–300, 600, 800–900) are deliberately not vendored: nothing uses them.

## Provenance

Retrieved from the Google Fonts repository (<https://github.com/google/fonts>)
with a sparse checkout of `ofl/lora`, `ofl/lato` and `ofl/jetbrainsmono`, then
copied in under the names above.

## Licence

Each family remains under the SIL Open Font License 1.1, included beside the
binaries as `OFL-Lora.txt`, `OFL-Lato.txt` and `OFL-JetBrainsMono.txt`, and
listed in the app under Settings › About › Open source licences.
