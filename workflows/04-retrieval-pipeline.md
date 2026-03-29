# Retrieval Pipeline

Triggered by `POST /search` or the first half of `POST /generate`. The query is embedded into both a dense vector (cosine similarity) and a sparse BM25 vector, sent to Qdrant as two simultaneous `Prefetch` arms, fused via Reciprocal Rank Fusion, and optionally reranked. An optional modality filter narrows results to a single chunk type.

```mermaid
flowchart TD
    Query["User Query\n'What is attention?'"] --> EmbedQ["embedder.embed([query_text])\n→ query_dense: list[float] 3072-dim"]
    Query --> SparseQ["compute_sparse_vectors([query_text])\n→ query_sparse: SparseVector"]

    EmbedQ --> PrefetchDense["Prefetch(\n  query=query_dense,\n  using='text_dense',\n  limit=top_k × 2\n)\nHNSW COSINE index\nm=16, ef_construct=100"]

    SparseQ --> PrefetchSparse["Prefetch(\n  query=query_sparse,\n  using='bm25_sparse',\n  limit=top_k × 2\n)\nsparse dot product"]

    PrefetchDense & PrefetchSparse --> RRF["FusionQuery(fusion=Fusion.RRF)\nscore = Σᵢ 1 / (60 + rankᵢ)\nlimit = top_k\n(Qdrant native RRF)"]

    RRF --> Candidates["top_k candidate dicts\nwith full payload"]

    Candidates --> ModalityQ{filter_modality\nset?}
    ModalityQ -->|yes| Filter["Qdrant payload filter\nFieldCondition(key='modality',\nmatch=MatchValue(value))\n'text' | 'image' | 'table'\n'formula' | 'algorithm'"]
    ModalityQ -->|no| RerankQ

    Filter --> RerankQ{rerank?}
    RerankQ -->|yes| Reranker["reranker.rerank(\n  query, candidates, top_n\n)\nscores each candidate\n(parallel async)"]
    RerankQ -->|no| Slice["candidates[:top_n]\nrerank_score = None"]

    Reranker --> Sort["sort by rerank_score DESC\n→ top_n"]

    Sort & Slice --> Results["list[ChunkResult]\nchunk_id, text, modality\npage, bbox, is_atomic\ncaption, rerank_score"]
```
