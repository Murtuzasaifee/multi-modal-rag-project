#!/usr/bin/env python3
"""CLI entry point for document parsing pipeline.

Usage:
    python scripts/parse.py document.pdf
    python scripts/parse.py ./docs/ --output ./parsed/ --format markdown
    python scripts/parse.py document.pdf --chunks --output ./chunks/
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

# Add src/ to Python path so we can import doc_parser
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from rich.console import Console
from rich.logging import RichHandler

from doc_parser.chunker import Chunk, structure_aware_chunking
from doc_parser.pipeline import DocumentParser, ParseResult
from doc_parser.post_processor import save_to_json

console = Console()
logger = logging.getLogger(__name__)

SUPPORTED_FORMATS = ("markdown", "json", "both")


def setup_logging(level: str) -> None:
    """Configure rich-enhanced logging."""
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(message)s",
        handlers=[RichHandler(console=console, rich_tracebacks=True)],
    )


def collect_input_files(input_path: Path) -> list[Path]:
    """Collect all supported input files from a path (file or directory).

    Args:
        input_path: Path to a single file or a directory.

    Returns:
        Sorted list of file paths to process.

    Raises:
        FileNotFoundError: If the path does not exist.
        ValueError: If no supported files are found.
    """
    if not input_path.exists():
        raise FileNotFoundError(f"Input path not found: {input_path}")

    if input_path.is_file():
        return [input_path]

    # Directory: collect all supported files
    supported = {".pdf", ".png", ".jpg", ".jpeg", ".tiff", ".bmp"}
    files = sorted(
        p for p in input_path.rglob("*")
        if p.is_file() and p.suffix.lower() in supported
    )
    if not files:
        raise ValueError(f"No supported files found in directory: {input_path}")
    return files


def save_chunks(result: ParseResult, output_dir: Path) -> None:
    """Save RAG-ready chunks JSON for all pages in the result.

    Args:
        result: ParseResult to chunk.
        output_dir: Directory to write the chunks JSON file.
    """
    all_chunks: list[Chunk] = []
    for page in result.pages:
        page_chunks = structure_aware_chunking(
            page.elements,
            source_file=Path(result.source_file).name,
            page=page.page_num,
        )
        all_chunks.extend(page_chunks)

    stem = Path(result.source_file).stem
    chunks_path = output_dir / f"{stem}_chunks.json"

    chunks_data = [
        {
            "text": c.text,
            "chunk_id": c.chunk_id,
            "page": c.page,
            "element_types": c.element_types,
            "bbox": c.bbox,
            "source_file": c.source_file,
            "is_atomic": c.is_atomic,
            "modality": c.modality,
            "image_base64": c.image_base64,
            "caption": c.caption,
        }
        for c in all_chunks
    ]

    chunks_path.write_text(
        json.dumps(chunks_data, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    logger.info("Saved %d chunks to %s", len(all_chunks), chunks_path)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Parse documents using PP-DocLayout-V3 + GLM-OCR via Z.AI MaaS API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/parse.py document.pdf
  python scripts/parse.py ./docs/ --output ./parsed/ --format markdown
  python scripts/parse.py document.pdf --chunks --format both
        """,
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Path to a document file (PDF/image) or directory of documents",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("./output"),
        help="Output directory (default: ./output/)",
    )
    parser.add_argument(
        "--format",
        choices=SUPPORTED_FORMATS,
        default="both",
        help="Output format: markdown, json, or both (default: both)",
    )
    parser.add_argument(
        "--chunks",
        action="store_true",
        help="Also output RAG-ready chunks JSON",
    )
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING"),
        default="INFO",
        help="Logging verbosity (default: INFO)",
    )
    return parser.parse_args()


def main() -> int:
    """Run the document parsing pipeline. Returns exit code."""
    args = parse_args()
    setup_logging(args.log_level)

    try:
        input_files = collect_input_files(args.input)
    except (FileNotFoundError, ValueError) as e:
        console.print(f"[red]Error:[/red] {e}")
        return 1

    output_dir = args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    console.print(
        f"[bold green]doc-parser[/bold green] — processing {len(input_files)} file(s) "
        f"→ [cyan]{output_dir}[/cyan]"
    )

    try:
        parser = DocumentParser()
    except ImportError as e:
        console.print(f"[red]Error:[/red] {e}")
        return 1

    exit_code = 0
    for file_path in input_files:
        try:
            console.print(f"  Parsing [yellow]{file_path.name}[/yellow]...", end=" ")
            result = parser.parse_file(file_path)

            # Save according to format flag
            if args.format in ("json", "both"):
                save_to_json(result, output_dir)
            elif args.format == "markdown":
                # Save only the .md file
                stem = file_path.stem
                md_path = output_dir / f"{stem}.md"
                all_md = "\n\n".join(p.markdown for p in result.pages if p.markdown)
                md_path.write_text(all_md, encoding="utf-8")

            if args.chunks:
                save_chunks(result, output_dir)

            console.print(
                f"[green]✓[/green] {len(result.pages)} page(s), "
                f"{result.total_elements} elements"
            )

        except Exception as e:
            console.print(f"[red]✗[/red] {e}")
            logger.error("Failed to parse %s: %s", file_path, e, exc_info=True)
            exit_code = 1

    if exit_code == 0:
        console.print(f"\n[bold green]Done![/bold green] Output saved to {output_dir}")
    else:
        console.print("\n[yellow]Completed with errors.[/yellow]")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
