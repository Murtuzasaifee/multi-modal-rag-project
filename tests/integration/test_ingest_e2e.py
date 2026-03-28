"""End-to-end ingestion integration test.

Skipped unless both Z_AI_API_KEY and OPENAI_API_KEY are set in the environment.
Requires a running Qdrant instance (local Docker or in-memory via qdrant-client).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

# ── skip markers ──────────────────────────────────────────────────────────────

_MISSING_KEYS: list[str] = [
    k for k in ("Z_AI_API_KEY", "OPENAI_API_KEY") if not os.environ.get(k)
]
pytestmark = pytest.mark.integration


@pytest.fixture(scope="module")
def _require_api_keys():
    if _MISSING_KEYS:
        pytest.skip(f"Integration test requires env vars: {', '.join(_MISSING_KEYS)}")


# ── helpers ───────────────────────────────────────────────────────────────────


def _sample_pdf() -> Path:
    """Return path to a sample PDF to ingest.

    Prefers a real PDF in the repo; falls back to a tiny synthetic one generated
    with PyMuPDF so the test is always self-contained.
    """
    candidates = [
        Path(__file__).parent / "fixtures" / "sample.pdf",
        Path(__file__).parent.parent.parent / "docling_report.pdf",
    ]
    for p in candidates:
        if p.exists():
            return p

    # Generate a one-page synthetic PDF using PyMuPDF
    try:
        import fitz

        doc = fitz.open()
        page = doc.new_page()
        page.insert_text((72, 72), "This is a test document for ingestion.")
        synthetic = Path(__file__).parent / "fixtures" / "synthetic.pdf"
        synthetic.parent.mkdir(parents=True, exist_ok=True)
        doc.save(str(synthetic))
        doc.close()
        return synthetic
    except Exception as exc:
        pytest.skip(f"Cannot create synthetic PDF: {exc}")


# ── tests ─────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_ingest_e2e_stores_at_least_one_point(_require_api_keys):
    """Parse a real PDF, embed it, upsert to Qdrant, and verify points exist."""
    from qdrant_client import AsyncQdrantClient

    from doc_parser.chunker import structure_aware_chunking
    from doc_parser.config import get_settings
    from doc_parser.ingestion.embedder import embed_chunks, get_embedder
    from doc_parser.ingestion.vector_store import QdrantDocumentStore
    from doc_parser.pipeline import DocumentParser

    settings = get_settings()
    # Use a dedicated test collection to avoid polluting production data
    settings.__dict__["qdrant_collection_name"] = "test_ingest_e2e"

    pdf_path = _sample_pdf()

    # Parse
    parser = DocumentParser()
    parse_result = parser.parse_file(pdf_path)
    assert parse_result.pages, "Parser returned no pages"

    # Chunk
    all_chunks = []
    for page_result in parse_result.pages:
        chunks = structure_aware_chunking(
            elements=page_result.elements,
            source_file=pdf_path.name,
            page=page_result.page_num,
        )
        all_chunks.extend(chunks)
    assert all_chunks, "No chunks produced"

    # Embed (skip image captioning to avoid extra cost in tests)
    embedder = get_embedder(settings)
    dense, sparse = await embed_chunks(all_chunks, embedder, settings)
    assert len(dense) == len(all_chunks)
    assert len(sparse) == len(all_chunks)

    # Upsert
    store = QdrantDocumentStore(settings)
    await store.create_collection(overwrite=True)
    count = await store.upsert_chunks(all_chunks, dense, sparse)
    assert count == len(all_chunks)

    # Verify points exist in Qdrant
    qdrant_client = AsyncQdrantClient(url=settings.qdrant_url)
    collection_info = await qdrant_client.get_collection(settings.qdrant_collection_name)
    assert collection_info.points_count >= 1

    # Cleanup
    await qdrant_client.delete_collection(settings.qdrant_collection_name)


@pytest.mark.asyncio
async def test_ingest_e2e_search_returns_results(_require_api_keys):
    """After ingestion, a hybrid search query should return at least one result."""
    from qdrant_client import AsyncQdrantClient

    from doc_parser.chunker import structure_aware_chunking
    from doc_parser.config import get_settings
    from doc_parser.ingestion.embedder import embed_chunks, get_embedder
    from doc_parser.ingestion.vector_store import QdrantDocumentStore
    from doc_parser.pipeline import DocumentParser

    settings = get_settings()
    settings.__dict__["qdrant_collection_name"] = "test_ingest_e2e_search"

    pdf_path = _sample_pdf()
    parser = DocumentParser()
    parse_result = parser.parse_file(pdf_path)

    all_chunks = []
    for page_result in parse_result.pages:
        all_chunks.extend(
            structure_aware_chunking(
                elements=page_result.elements,
                source_file=pdf_path.name,
                page=page_result.page_num,
            )
        )

    embedder = get_embedder(settings)
    dense, sparse = await embed_chunks(all_chunks, embedder, settings)

    store = QdrantDocumentStore(settings)
    await store.create_collection(overwrite=True)
    await store.upsert_chunks(all_chunks, dense, sparse)

    results = await store.search(
        query_text="document",
        embedder=embedder,
        settings=settings,
        top_k=5,
    )
    assert len(results) >= 1
    assert "text" in results[0]

    # Cleanup
    qdrant_client = AsyncQdrantClient(url=settings.qdrant_url)
    await qdrant_client.delete_collection(settings.qdrant_collection_name)
