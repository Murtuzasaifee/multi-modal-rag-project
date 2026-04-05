"""Ingestion CLI: parse documents (PDF/images) → chunk → caption → embed → upsert to Qdrant."""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

# Allow running from the project root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, TimeElapsedColumn

from doc_parser.chunker import Chunk, structure_aware_chunking
from doc_parser.config import configure_logging, get_settings
from doc_parser.ingestion.embedder import embed_chunks, get_embedder
from doc_parser.ingestion.image_captioner import enrich_image_chunks
from doc_parser.ingestion.vector_store import QdrantDocumentStore
from doc_parser.pipeline import DocumentParser

console = Console()
logger = logging.getLogger(__name__)


_SUPPORTED_EXTENSIONS: frozenset[str] = frozenset(
    {".pdf", ".png", ".jpg", ".jpeg", ".tiff", ".bmp"}
)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ingest documents (PDF or images) into a Qdrant hybrid vector store."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Document file or directory of documents to ingest.",
    )
    parser.add_argument(
        "--no-captions",
        action="store_true",
        default=False,
        help="Skip GPT-4o image captioning (faster, text-only ingestion).",
    )
    parser.add_argument(
        "--collection",
        type=str,
        default=None,
        help="Override Qdrant collection name from settings.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Delete and recreate the Qdrant collection before ingesting.",
    )
    parser.add_argument(
        "--max-chunk-tokens",
        type=int,
        default=512,
        help="Maximum tokens per chunk (default: 512).",
    )
    return parser.parse_args()


def _collect_files(input_path: Path) -> list[Path]:
    """Return a list of supported document paths from a file or directory."""
    if input_path.is_file():
        if input_path.suffix.lower() not in _SUPPORTED_EXTENSIONS:
            console.print(f"[red]Error:[/red] {input_path} is not a supported document file.")
            sys.exit(1)
        return [input_path]
    if input_path.is_dir():
        files = sorted(p for p in input_path.rglob("*") if p.suffix.lower() in _SUPPORTED_EXTENSIONS)
        if not files:
            console.print(f"[yellow]Warning:[/yellow] No supported document files found in {input_path}")
        return files
    console.print(f"[red]Error:[/red] {input_path} does not exist.")
    sys.exit(1)


async def _ingest_file(
    file_path: Path,
    parser: DocumentParser,
    store: QdrantDocumentStore,
    caption_enabled: bool,
    max_chunk_tokens: int,
    progress: Progress,
) -> dict[str, int]:
    """Run the full ingest pipeline for a single document file.

    Returns a summary dict with counts by modality.
    """
    from openai import AsyncOpenAI

    settings = get_settings()
    openai_key = (
        settings.openai_api_key.get_secret_value() if settings.openai_api_key else None
    )
    openai_client = AsyncOpenAI(api_key=openai_key)
    embedder = get_embedder(settings)

    task = progress.add_task(f"[cyan]{file_path.name}[/cyan]", total=None)

    # Step 1: Parse
    progress.update(task, description=f"[cyan]{file_path.name}[/cyan] — parsing")
    parse_result = parser.parse_file(file_path)

    # Step 2: Chunk
    progress.update(task, description=f"[cyan]{file_path.name}[/cyan] — chunking")
    all_chunks: list[Chunk] = []
    for page_result in parse_result.pages:
        page_chunks = structure_aware_chunking(
            elements=page_result.elements,
            source_file=file_path.name,
            page=page_result.page_num,
            max_chunk_tokens=max_chunk_tokens,
        )
        all_chunks.extend(page_chunks)

    # Step 3: Enrich image chunks
    if caption_enabled and settings.image_caption_enabled:
        progress.update(task, description=f"[cyan]{file_path.name}[/cyan] — captioning images")
        all_chunks = await enrich_image_chunks(
            chunks=all_chunks,
            pdf_path=file_path,
            client=openai_client,
        )

    # Step 4: Embed (dense + sparse)
    progress.update(task, description=f"[cyan]{file_path.name}[/cyan] — embedding")
    dense_embeddings, sparse_vectors = await embed_chunks(
        chunks=all_chunks,
        embedder=embedder,
        settings=settings,
    )

    # Step 5: Upsert
    progress.update(task, description=f"[cyan]{file_path.name}[/cyan] — upserting")
    await store.upsert_chunks(
        chunks=all_chunks,
        dense_embeddings=dense_embeddings,
        sparse_vectors=sparse_vectors,
    )

    progress.remove_task(task)

    # Build summary counts by modality
    summary: dict[str, int] = {}
    for chunk in all_chunks:
        summary[chunk.modality] = summary.get(chunk.modality, 0) + 1
    return summary


async def main() -> None:
    """Entry point for the ingest CLI."""
    args = _parse_args()
    settings = get_settings()
    configure_logging(settings.log_level)

    if args.collection:
        # Override collection name without mutating the singleton
        settings.__dict__["qdrant_collection_name"] = args.collection

    file_paths = _collect_files(args.input)
    if not file_paths:
        return

    parser = DocumentParser()
    store = QdrantDocumentStore(settings)

    # Ensure collection exists (or recreate it)
    await store.create_collection(overwrite=args.overwrite)

    total_summary: dict[str, int] = {}

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        TimeElapsedColumn(),
        console=console,
    ) as progress:
        for file_path in file_paths:
            summary = await _ingest_file(
                file_path=file_path,
                parser=parser,
                store=store,
                caption_enabled=not args.no_captions,
                max_chunk_tokens=args.max_chunk_tokens,
                progress=progress,
            )
            for modality, count in summary.items():
                total_summary[modality] = total_summary.get(modality, 0) + count

    # Print final summary
    console.print("\n[bold green]Ingestion complete[/bold green]")
    console.print(f"  Collection : [cyan]{settings.qdrant_collection_name}[/cyan]")
    console.print(f"  Files      : [cyan]{len(file_paths)}[/cyan]")
    for modality, count in sorted(total_summary.items()):
        console.print(f"  {modality:<10}: [cyan]{count}[/cyan] chunks")
    total = sum(total_summary.values())
    console.print(f"  {'Total':<10}: [bold cyan]{total}[/bold cyan] chunks")


if __name__ == "__main__":
    asyncio.run(main())
