"""Catalog image QA: is every puzzle piece of this image readable, and is it free of AI artifacts?

For each image this tool:
  1. cuts it into its 15x15 = 225 piece-patches (what one piece of a 225-piece
     puzzle shows) and has a vision model classify every patch:
     OBJECT (nameable thing) / TEXTURE (nameable material) / MUSH (can't tell),
  2. sends the full image to a vision model to hunt AI-generation artifacts
     (fake text, melted structure, fused objects, impossible geometry),
  3. prints a verdict: PASS, or CHECK when mush > 15% of patches or any
     high-severity artifact is found.

Usage:
  export OPENAI_API_KEY=sk-...
  python3 tool/image_qa/check_image.py assets/images/cozy/reading_nook.webp [more images...]

With --flags-only, step 1 is skipped: contact sheets are still cut locally
(free, for eyeballing) but only the artifact hunt runs (~5 cents/image
instead of ~75 cents). The verdict then rests on artifacts alone.

Reports and contact sheets land in tool/image_qa/out/<image-stem>/ (gitignored).
A finished image is never re-billed: its cached report is reused as long as
the image bytes are unchanged and the report's mode covers the request (a
full report also answers a flags-only request). Exit status is nonzero when
any image failed or the batch was aborted.
Cost is roughly $0.20-0.25 per image. Models can be overridden with the
PATCH_MODEL / FLAG_MODEL env vars.
"""
import base64
import hashlib
import concurrent.futures
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
OUT_ROOT = HERE / "out"

KEY = os.environ.get("OPENAI_API_KEY")
if not KEY:
    sys.exit("OPENAI_API_KEY is not set")

PATCH_MODEL = os.environ.get("PATCH_MODEL", "gpt-5.5")
FLAG_MODEL = os.environ.get("FLAG_MODEL", "gpt-5.5")

GRID = 15
MUSH_PCT_LIMIT = 15.0
WORKERS = int(os.environ.get("QA_WORKERS", "2"))
VALID_LABELS = ("OBJECT", "TEXTURE", "MUSH")


class OutOfCredits(RuntimeError):
    """Account balance exhausted — retrying is pointless, stop the whole batch."""

PATCH_PROMPT = """The attached image is a 5x5 contact sheet of square patches cut from ONE picture. \
The label under each patch (e.g. A1) is its id. A patch is exactly one piece of a 225-piece jigsaw puzzle.

Classify EVERY one of these patch ids: {ids}

Categories — judge each patch strictly ON ITS OWN, ignoring what neighboring patches show:
- OBJECT: looking at this patch alone, you can confidently name a specific thing (door knob, bread loaf, tower)
- TEXTURE: you can confidently name the material or pattern (stone, fabric, foliage, sky, wall) but no specific object
- MUSH: you could NOT confidently say what this is if you saw only this patch - vague strokes or blobs \
that could be several different things

Be honest about MUSH: if naming it requires guessing or context from other patches, it is MUSH. \
But clear painterly brushwork that still reads as a nameable thing is OBJECT or TEXTURE.

Return ONLY JSON: {{"cells": {{"A1": "OBJECT", ...}}}} with ALL 25 ids listed above."""

FLAG_PROMPT = """This painted-style image will be cut into jigsaw puzzle pieces, so players inspect \
every small detail closely. Hunt for AI-generation artifacts that contradict reality:
1. letter-like squiggles / fake text (signs, book spines, labels)
2. melted or impossible structure (railing merging into wall, fence stopping mid-air, bent frames)
3. objects fused together (chair leg growing from a table, limbs blending into surfaces)
4. impossible geometry (roof lines that cannot meet, stairs into nothing, broken perspective)

Do NOT report soft painterly abstraction or loose brushwork - only details that actively contradict reality.
Return ONLY JSON: {"flags": [{"what": "...", "where": "...", "severity": "high" or "low"}]} - empty list if clean."""


def api_call(model, content, max_tokens=12000):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "response_format": {"type": "json_object"},
        "max_completion_tokens": max_tokens,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=280) as resp:
                data = json.load(resp)
            usage = data.get("usage", {})
            return json.loads(data["choices"][0]["message"]["content"]), usage
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if "insufficient_quota" in detail or "credit_balance_exhausted" in detail:
                raise OutOfCredits("OpenAI account has no credits remaining") from e
            if e.code in (429, 500, 502, 503) and attempt < 5:
                time.sleep(10 * 2 ** attempt)   # rate limit / transient: back off and retry
                continue
            raise
        except (urllib.error.URLError, OSError):
            if attempt < 5:   # broken pipe / SSL hiccup under load: retryable
                time.sleep(10 * 2 ** attempt)
                continue
            raise
    raise RuntimeError("unreachable")


def image_part(path, detail="high"):
    b64 = base64.b64encode(pathlib.Path(path).read_bytes()).decode()
    mime = "image/jpeg" if path.suffix == ".jpg" else "image/png"
    return {"type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}", "detail": detail}}


def check_image(img_path, flags_only=False):
    img_path = pathlib.Path(img_path).resolve()
    out_dir = OUT_ROOT / img_path.stem
    sha = hashlib.sha256(img_path.read_bytes()).hexdigest()
    mode = "flags-only" if flags_only else "full"

    existing = out_dir / "report.json"
    if existing.exists():   # resume: a finished image is never re-billed...
        cached = json.loads(existing.read_text())
        # ...but only for the same image bytes and a mode that covers the
        # request (full answers flags-only; the reverse must re-run).
        if cached.get("source_sha256") == sha and cached.get("mode") in ("full", mode):
            return cached
    out_dir.mkdir(parents=True, exist_ok=True)

    # The Swift cutter reads whatever NSImage reads; webp works on modern macOS,
    # but convert defensively so jpg/webp both upload as png/jpg consistently.
    src = img_path
    if img_path.suffix == ".webp":
        src = out_dir / "source.png"
        subprocess.run(["sips", "-s", "format", "png", str(img_path), "--out", str(src)],
                       check=True, capture_output=True)

    subprocess.run(["swift", str(HERE / "make_grids.swift"), str(src), str(out_dir)],
                   check=True, capture_output=True)
    sheets = sorted(out_dir.glob("sheet-*.jpg"))

    cells, usage_in, usage_out = {}, 0, 0
    for n, sheet in enumerate([] if flags_only else sheets):
        band_row, band_col = n // 3, n % 3
        expected = [f"{chr(65 + band_row * 5 + r)}{band_col * 5 + c + 1}"
                    for r in range(5) for c in range(5)]
        content = [{"type": "text", "text": PATCH_PROMPT.format(ids=", ".join(expected))},
                   image_part(sheet)]
        for attempt in range(2):   # one retry if the model skips or mislabels cells
            result, u = api_call(PATCH_MODEL, content)
            usage_in += u.get("prompt_tokens", 0)
            usage_out += u.get("completion_tokens", 0)
            cells.update({k.upper(): v.upper() for k, v in result.get("cells", {}).items()
                          if k.upper() in expected
                          and isinstance(v, str) and v.upper() in VALID_LABELS})
            if all(e in cells for e in expected):
                break

    # A full verdict over a partial grid would silently understate mush, so a
    # grid that is still incomplete after the retries fails the image instead.
    if not flags_only and len(cells) != GRID * GRID:
        raise RuntimeError(
            f"only {len(cells)}/{GRID * GRID} patches validly classified after retries")

    flags_result, u = api_call(FLAG_MODEL,
        [{"type": "text", "text": FLAG_PROMPT}, image_part(src)])
    usage_in += u.get("prompt_tokens", 0)
    usage_out += u.get("completion_tokens", 0)
    flags = flags_result.get("flags", [])

    counts = {label: 0 for label in VALID_LABELS}
    for label in cells.values():   # only valid labels are ever stored in cells
        counts[label] += 1
    mush_pct = None if flags_only else 100 * counts["MUSH"] / len(cells)
    high_flags = [f for f in flags if f.get("severity") == "high"]
    verdict = "CHECK" if (high_flags or (mush_pct or 0) > MUSH_PCT_LIMIT) else "PASS"

    report = {
        "image": str(img_path), "model": PATCH_MODEL, "verdict": verdict,
        "mode": mode, "source_sha256": sha,
        "counts": None if flags_only else counts,
        "mush_pct": None if flags_only else round(mush_pct, 1),
        "mush_cells": sorted(c for c, v in cells.items() if v == "MUSH"),
        "flags": flags, "cells": cells,
        "tokens": {"input": usage_in, "output": usage_out},
    }
    (out_dir / "report.json").write_text(json.dumps(report, indent=2))
    return report


def main():
    args = sys.argv[1:]
    flags_only = "--flags-only" in args
    images = [a for a in args if a != "--flags-only"]
    if not images:
        sys.exit("usage: check_image.py [--flags-only] <image> [<image> ...]")
    reports, failed = [], []
    aborted = False
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(check_image, p, flags_only): p for p in images}
        for fut in concurrent.futures.as_completed(futures):
            path = futures[fut]
            try:
                r = fut.result()
            except OutOfCredits:
                aborted = True
                for f in futures:   # no credits left: stop burning attempts
                    f.cancel()
                print("\nSTOPPED: OpenAI account has no credits remaining — "
                      "add credits, then re-run the same command (finished images are skipped).",
                      flush=True)
                break
            except Exception as e:   # one bad image shouldn't kill the batch
                failed.append(path)
                print(f"ERROR {path}: {e}", flush=True)
                continue
            reports.append(r)
            mush = "—" if r.get("mush_pct") is None else f"{r['mush_pct']}%"
            line = f"{r['verdict']:5} {pathlib.Path(r['image']).name}" \
                   f"  mush {mush}  flags {len(r['flags'])}"
            print(line, flush=True)
            for f in r["flags"]:
                print(f"      [{f.get('severity')}] {f.get('what')} — {f.get('where')}", flush=True)

    checks = [r for r in reports if r["verdict"] == "CHECK"]
    tok_in = sum(r["tokens"]["input"] for r in reports)
    tok_out = sum(r["tokens"]["output"] for r in reports)
    print(f"\n{len(reports)} checked: {len(reports) - len(checks)} PASS, {len(checks)} CHECK"
          + (f", {len(failed)} ERROR" if failed else ""))
    for r in checks:
        print(f"  CHECK -> {pathlib.Path(r['image']).name}")
    print(f"tokens: {tok_in} in / {tok_out} out")
    if failed or aborted:   # scripts chaining on this tool must see the failure
        sys.exit(1)


if __name__ == "__main__":
    main()
