"""POST /search endpoint."""
from __future__ import annotations

import time

from fastapi import APIRouter, HTTPException
from loguru import logger

from doc_parser.api.dependencies import get_embedder_dep, get_reranker_dep, get_store
from doc_parser.api.schemas import ChunkResult, SearchRequest, SearchResponse
from doc_parser.config import get_settings

router = APIRouter()


@router.post("", response_model=SearchResponse)
async def search(req: SearchRequest) -> SearchResponse:
    """Hybrid search with optional reranking.

    1. Embed query with OpenAI.
    2. Hybrid search (dense + sparse RRF) in Qdrant.
    3. Optionally rerank candidates with the configured backend.
    4. Return ranked results with scores and latency.
    """
    settings = get_settings()
    store = get_store()
    embedder = get_embedder_dep()
    reranker = get_reranker_dep()

    top_n = req.top_n if req.top_n is not None else settings.reranker_top_n

    t0 = time.perf_counter()

    try:
        candidates = await store.search(
            query_text=req.query,
            embedder=embedder,
            settings=settings,
            top_k=req.top_k,
            filter_modality=req.filter_modality,
        )
    except Exception as exc:
        logger.exception("Search failed: {}", exc)
        raise HTTPException(status_code=502, detail=f"Vector store search failed: {exc}") from exc

    total_candidates = len(candidates)
    logger.debug("Retrieved {} candidates from Qdrant", total_candidates)

    if req.rerank and candidates:
        try:
            candidates = await reranker.rerank(req.query, candidates, top_n=top_n)
        except Exception as exc:
            logger.exception("Reranking failed: {}", exc)
            raise HTTPException(status_code=502, detail=f"Reranking failed: {exc}") from exc
    else:
        # Attach null scores for raw results and slice to top_n
        for c in candidates:
            c.setdefault("rerank_score", None)
        candidates = candidates[:top_n]

    latency_ms = (time.perf_counter() - t0) * 1000

    results = [
        ChunkResult(
            chunk_id=c.get("chunk_id", ""),
            text=c.get("text", ""),
            source_file=c.get("source_file", ""),
            page=c.get("page", 0),
            modality=c.get("modality", "text"),
            element_types=c.get("element_types", []),
            bbox=c.get("bbox"),
            is_atomic=c.get("is_atomic", False),
            caption=c.get("caption"),
            rerank_score=c.get("rerank_score"),
            # image_base64 omitted by default (large payload)
        )
        for c in candidates
    ]

    return SearchResponse(
        query=req.query,
        backend=settings.reranker_backend,
        total_candidates=total_candidates,
        results=results,
        latency_ms=round(latency_ms, 2),
    )
