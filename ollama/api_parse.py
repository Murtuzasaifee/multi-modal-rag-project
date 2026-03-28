#!/usr/bin/env python3
"""
Test GLM-OCR parsing via Z.AI cloud MaaS API.

Produces the same *_elements.json + *.md output as test_parse.py so that
ollama/visualize.py can load and render the results unchanged.

Prerequisites:
    Z_AI_API_KEY set in .env (project root) or exported in the shell

Usage:
    uv run python ollama/api_parse.py data/raw/paper.pdf
    uv run python ollama/api_parse.py data/raw/figure.png
    uv run python ollama/api_parse.py data/raw/paper.pdf --show-elements
    uv run python ollama/api_parse.py data/raw/paper.pdf --output ./ollama/output/
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

# ── Attempt to load .env so Z_AI_API_KEY is available without exporting ───────
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / ".env")
except ImportError:
    pass  # python-dotenv optional; user can export Z_AI_API_KEY directly

# ── Attempt to import glmocr SDK ──────────────────────────────────────────────
try:
    from glmocr import GlmOcr
except ImportError:
    print("ERROR: glmocr not installed. Run: uv pip install glmocr")
    sys.exit(1)


def _count_pdf_pages(pdf_path: Path) -> int:
    """Return the number of pages in a PDF using PyMuPDF.

    Returns 0 if fitz is not available; the caller will skip the explicit
    page-range arguments in that case (SDK may default to page 1 only).
    """
    try:
        import fitz  # PyMuPDF
        doc = fitz.open(str(pdf_path))
        n = len(doc)
        doc.close()
        return n
    except ImportError:
        return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Test GLM-OCR parsing via Z.AI cloud MaaS API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("input", type=Path, help="PDF or image file to parse")
    p.add_argument(
        "--output", "-o",
        type=Path,
        default=Path(__file__).parent / "output",
        help="Directory to save results (default: ollama/output/)",
    )
    p.add_argument(
        "--show-elements",
        action="store_true",
        default=False,
        help="Print raw JSON elements of the first page (in addition to Markdown)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if not args.input.exists():
        print(f"ERROR: File not found: {args.input}")
        return 1

    api_key = os.environ.get("Z_AI_API_KEY")
    if not api_key:
        print("ERROR: Z_AI_API_KEY is not set.")
        print("  Add it to .env in the project root, or run:")
        print("  export Z_AI_API_KEY=<your-key>")
        return 1

    print(f"Parser  : GLM-OCR via Z.AI MaaS API")
    print(f"Input   : {args.input}")

    # ── Build page-range kwargs (cloud SDK defaults to page 1 only for PDFs) ──
    parse_kwargs: dict = {}
    if args.input.suffix.lower() == ".pdf":
        n_pages = _count_pdf_pages(args.input)
        if n_pages > 0:
            parse_kwargs["start_page_id"] = 0
            parse_kwargs["end_page_id"] = n_pages - 1
            print(f"Pages   : {n_pages} (explicit range 0–{n_pages - 1} sent to API)")
        else:
            print("Pages   : unknown (PyMuPDF not available — API may parse page 1 only)")
    print()

    # ── Parse ─────────────────────────────────────────────────────────────────
    t0 = time.perf_counter()
    try:
        # Passing api_key with no config_path lets the SDK use MaaS defaults.
        # Note: never pass a config with maas.enabled=false together with an
        # api_key — the SDK would still force MaaS mode but with a broken config.
        parser = GlmOcr(api_key=api_key)
        result = parser.parse(str(args.input), **parse_kwargs)
    except Exception as exc:
        print(f"ERROR: Parsing failed: {exc}")
        print()
        print("Troubleshooting:")
        print("  1. Is Z_AI_API_KEY correct and still valid?")
        print("  2. Do you have remaining API quota?")
        print("  3. Is the file a supported format (PDF, PNG, JPEG)?")
        return 1

    elapsed = time.perf_counter() - t0

    # ── Normalise output ───────────────────────────────────────────────────────
    # Cloud SDK: json_result is list[list[dict]] — one inner list per page,
    # each element dict has {index, label, content, bbox_2d}.
    # This is identical to the Ollama output schema, so visualize.py works as-is.
    pages: list[list[dict]] = result.json_result if isinstance(result.json_result, list) else []
    n_pages_out = len(pages)
    n_elements = sum(len(p) for p in pages) if pages and isinstance(pages[0], list) else 0

    print(f"Parsed in {elapsed:.1f}s")
    print(f"   Pages    : {n_pages_out}")
    print(f"   Elements : {n_elements}")
    print()

    # ── Markdown output ───────────────────────────────────────────────────────
    md: str = result.markdown_result or ""
    if md:
        print("-" * 60)
        print("MARKDOWN OUTPUT")
        print("-" * 60)
        print(md[:2000])
        if len(md) > 2000:
            print(f"\n... ({len(md) - 2000} more characters)")
        print()

    # ── Element JSON (optional) ───────────────────────────────────────────────
    if args.show_elements and pages:
        print("-" * 60)
        print("ELEMENT JSON (first page)")
        print("-" * 60)
        first_page = pages[0] if isinstance(pages[0], list) else pages
        print(json.dumps(first_page[:5], indent=2, ensure_ascii=False))
        if len(first_page) > 5:
            print(f"  ... ({len(first_page) - 5} more elements)")
        print()

    # ── Save to disk ──────────────────────────────────────────────────────────
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        stem = args.input.stem

        if md:
            md_path = args.output / f"{stem}.md"
            md_path.write_text(md, encoding="utf-8")
            print(f"Saved Markdown : {md_path}")

        if pages:
            json_path = args.output / f"{stem}_elements.json"
            json_path.write_text(
                json.dumps(pages, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            print(f"Saved JSON     : {json_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
