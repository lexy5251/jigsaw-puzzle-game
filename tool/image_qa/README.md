# Image QA — "does every piece make sense?"

Checks a catalog image the way a puzzle player experiences it, before you add
it to the app. No device needed.

What it checks:

1. **Piece readability** — cuts the image into its 225 piece-patches
   (a 15x15 grid, the largest puzzle size) and a vision model classifies each
   patch: OBJECT (nameable thing), TEXTURE (nameable material), or MUSH
   (can't tell what it is when seen alone).
2. **AI artifacts** — the full image is scanned for the details that draw
   "garbage details" reviews: fake text squiggles, melted structure, fused
   objects, impossible geometry.

Verdict per image: **PASS**, or **CHECK** when mush > 15% of patches or any
high-severity artifact is found. CHECK means: look at the report, then decide
to keep or regenerate.

## Usage

```sh
export OPENAI_API_KEY=sk-...
python3 tool/image_qa/check_image.py assets/images/cozy/reading_nook.webp
# or a whole batch:
python3 tool/image_qa/check_image.py assets/images/flowers/*.webp
```

Output per image in `tool/image_qa/out/<stem>/` (gitignored):
`report.json` (verdict, per-cell classes, flags, token usage) and the 9
labeled contact sheets (`sheet-*.jpg`) to eyeball any flagged cells
(labels A1–O15: row letter top to bottom, column number left to right).

Cost: ~$0.20–0.25 per image (gpt-5.5). Runs 4 images in parallel.

## Notes

- The judge model was validated 2026-11-23 against hand labels on two catalog
  images: verdict-level agreement 100%, cell-level mush agreement ~88%
  (disagreements were borderline patches, defensible both ways). The cheap
  mini models are too lenient (found zero mush) — don't downgrade PATCH_MODEL.
- The artifact pass is the important gate: market research shows review
  backlash targets contradicting details, not soft painterly patches.
- Needs macOS (uses `swift` + `sips` for cutting/conversion), Python 3
  stdlib only.
