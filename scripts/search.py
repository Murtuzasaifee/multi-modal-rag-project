"""Search CLI: query → retrieve → rerank → print results.

Examples:
    python scripts/search.py "What is the transformer attention mechanism?"
    python scripts/search.py "figure showing accuracy vs recall" --filter-modality image
    python scripts/search.py "query" --top-k 20 --top-n 5 --backend jina
    python scripts/search.py "query" --no-rerank
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from rich.console import Console
from rich.table import Table

from doc_parser.config import configure_logging, get_settings
from doc_parser.ingestion.embedder import get_embedder
from doc_parser.ingestion.vector_store import QdrantDocumentStore
from doc_parser.retrieval.reranker import get_reranker

console = Console()
logger = logging.getLogger(__name__)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query the Qdrant index, optionally re-rank results."
    )
    parser.add_argument("query", type=str, help="Natural-language search query.")
    parser.add_argument(
        "--top-k",
        type=int,
        default=20,
        help="Number of candidates to retrieve before re-ranking (default: 20).",
    )
    parser.add_argument(
        "--top-n",
        type=int,
        default=None,
        help="Number of results to keep after re-ranking (default: RERANKER_TOP_N from settings).",
    )
    parser.add_argument(
        "--backend",
        type=str,
        default=None,
        choices=["openai", "jina", "bge", "qwen"],
        help="Re-ranker backend to use (overrides RERANKER_BACKEND from .env).",
    )
    parser.add_argument(
        "--filter-modality",
        type=str,
        default=None,
        choices=["text", "image", "table", "formula"],
        help="Restrict retrieval to a specific modality.",
    )
    parser.add_argument(
        "--no-rerank",
        action="store_true",
        default=False,
        help="Skip re-ranking and print raw retrieval results.",
    )
    parser.add_argument(
        "--collection",
        type=str,
        default=None,
        help="Override Qdrant collection name from settings.",
    )
    return parser.parse_args()


def _print_results(results: list[dict], title: str) -> None:
    """Render a rich table of search results."""
    table = Table(title=title, show_lines=True)
    table.add_column("#", style="bold cyan", width=3)
    table.add_column("Score", width=8)
    table.add_column("Modality", width=10)
    table.add_column("Source", width=20)
    table.add_column("Page", width=5)
    table.add_column("Text", no_wrap=False)

    for i, r in enumerate(results, 1):
        score = r.get("rerank_score")
        score_str = f"{score:.4f}" if score is not None else "—"
        text = (r.get("text") or "").strip()
        modality = r.get("modality", "?")
        source = r.get("source_file", "?")
        page = str(r.get("page", "?"))

        # Truncate long text for display
        display_text = text[:200] + ("…" if len(text) > 200 else "")

        # Add visual indicator for image chunks
        if modality == "image" and r.get("image_base64"):
            display_text = f"[dim][IMAGE][/dim] {display_text}"

        table.add_row(str(i), score_str, modality, source, page, display_text)

    console.print(table)


async def main() -> None:
    """Entry point for the search CLI."""
    args = _parse_args()
    settings = get_settings()
    configure_logging(settings.log_level)

    if args.collection:
        settings.__dict__["qdrant_collection_name"] = args.collection

    # Allow --backend CLI flag to override settings
    if args.backend:
        settings.__dict__["reranker_backend"] = args.backend

    top_n = args.top_n if args.top_n is not None else settings.reranker_top_n

    embedder = get_embedder(settings)
    store = QdrantDocumentStore(settings)

    console.print(f"\n[bold]Query:[/bold] {args.query}")
    console.print(
        f"[dim]Collection: {settings.qdrant_collection_name} | "
        f"top-k: {args.top_k} | "
        f"modality filter: {args.filter_modality or 'all'}[/dim]\n"
    )

    # Step 1: Retrieve
    with console.status("[cyan]Retrieving candidates from Qdrant…[/cyan]"):
        candidates = await store.search(
            query_text=args.query,
            embedder=embedder,
            settings=settings,
            top_k=args.top_k,
            filter_modality=args.filter_modality,
        )

    console.print(f"[green]Retrieved {len(candidates)} candidates.[/green]")

    if args.no_rerank:
        _print_results(candidates, f"Raw Results (top-{len(candidates)})")
        return

    # Step 2: Re-rank
    backend = settings.reranker_backend
    console.print(f"[dim]Re-ranking with backend: {backend}[/dim]")

    with console.status(f"[cyan]Re-ranking with {backend}…[/cyan]"):
        reranker = get_reranker(settings)
        reranked = await reranker.rerank(args.query, candidates, top_n=top_n)

    _print_results(reranked, f"Re-ranked Results (top-{len(reranked)}, backend={backend})")


if __name__ == "__main__":
    asyncio.run(main())
