#!/usr/bin/env python3
"""
Test GLM-OCR parsing via local Ollama.

Prerequisites:
    ollama pull glm-ocr:latest
    ollama serve   (if not already running)

Usage:
    uv run python ollama/test_parse.py data/raw/test_page1.pdf
    uv run python ollama/test_parse.py data/raw/figure.png
    uv run python ollama/test_parse.py data/raw/test_page1.pdf --output ./ollama/output/
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# ── Attempt to import glmocr SDK ──────────────────────────────────────────────
try:
    from glmocr import GlmOcr
except ImportError:
    print("ERROR: glmocr not installed. Run: uv pip install glmocr")
    sys.exit(1)

# ── Config lives next to this script ─────────────────────────────────────────
_CONFIG = Path(__file__).parent / "config.yaml"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Test GLM-OCR parsing via local Ollama (glm-ocr:latest)",
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
        help="Print raw JSON elements (in addition to Markdown)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if not args.input.exists():
        print(f"ERROR: File not found: {args.input}")
        return 1

    if not _CONFIG.exists():
        print(f"ERROR: Config not found: {_CONFIG}")
        return 1

    print(f"Parser  : GLM-OCR via Ollama (glm-ocr:latest)")
    print(f"Config  : {_CONFIG}")
    print(f"Input   : {args.input}")
    print()

    # ── Parse ─────────────────────────────────────────────────────────────────
    t0 = time.perf_counter()
    try:
        parser = GlmOcr(config_path=str(_CONFIG))
        # save_layout_visualization=False: avoids two glmocr 0.1.3 SDK bugs:
        #   1. visualization_utils.py:171 — `numpy_array or []` raises ValueError
        #   2. Queue(maxsize=None) in error handler raises TypeError
        result = parser.parse(str(args.input), save_layout_visualization=False)
    except Exception as exc:
        print(f"ERROR: Parsing failed: {exc}")
        print()
        print("Troubleshooting:")
        print("  1. Is Ollama running?          ollama serve")
        print("  2. Is the model pulled?        ollama list")
        print("  3. Is the model name correct?  ollama show glm-ocr:latest")
        return 1

    elapsed = time.perf_counter() - t0

    # ── Summarise ─────────────────────────────────────────────────────────────
    pages = result.json_result if isinstance(result.json_result, list) else []
    n_pages = len(pages)
    n_elements = sum(len(p) for p in pages) if pages and isinstance(pages[0], list) else 0

    print(f"Parsed in {elapsed:.1f}s")
    print(f"   Pages    : {n_pages}")
    print(f"   Elements : {n_elements}")
    print()

    # ── Markdown output ───────────────────────────────────────────────────────
    md = result.markdown_result or ""
    if md:
        print("-" * 60)
        print("MARKDOWN OUTPUT")
        print("-" * 60)
        # Print first 2000 chars to avoid flooding the terminal
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

    # ── Save to disk (optional) ───────────────────────────────────────────────
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        stem = args.input.stem

        # Save Markdown
        if md:
            md_path = args.output / f"{stem}.md"
            md_path.write_text(md, encoding="utf-8")
            print(f"Saved Markdown : {md_path}")

        # Save JSON elements
        if pages:
            json_path = args.output / f"{stem}_elements.json"
            json_path.write_text(
                json.dumps(pages, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            print(f"Saved JSON     : {json_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
