# Hybrid Search and RRF Fusion

`store.search()` embeds the query into both vector spaces, sends them as two independent `Prefetch` arms to Qdrant, and combines their ranked lists using Reciprocal Rank Fusion (RRF). RRF score = Σᵢ 1/(k + rankᵢ) where k = 60. Because RRF operates on rank positions rather than raw scores, it is robust to score-scale mismatches between dense cosine similarity and sparse dot-product — a key reason it outperforms simple score averaging.

```mermaid
flowchart LR
    QText["query_text: str"] --> EmbQ["embedder.embed([query_text])\n→ query_dense  list[float] 3072-dim"]
    QText --> SprQ["compute_sparse_vectors([query_text])\n→ query_sparse  SparseVector"]

    EmbQ --> PfDense["Prefetch(\n  query=query_dense,\n  using='text_dense',\n  limit=top_k × 2\n)\nHNSW COSINE\nm=16, ef_construct=100\nretrieves dense rank list"]

    SprQ --> PfSparse["Prefetch(\n  query=query_sparse,\n  using='bm25_sparse',\n  limit=top_k × 2\n)\nSparse dot product\nfeature-hashed TF\nretrieves BM25 rank list"]

    PfDense & PfSparse --> Qdrant[("Qdrant\ncollection: 'documents'")]

    Qdrant --> RRF["FusionQuery(fusion=Fusion.RRF)\n\nFor each candidate:\n  rrf_score = 1/(60 + rank_dense)\n            + 1/(60 + rank_sparse)\n\nCandidates only in one list:\n  missing rank → term = 0\n\nlimit = top_k\nsort by rrf_score DESC"]

    RRF --> TopK["top_k ScoredPoints\nwith_payload=True"]

    TopK --> Filter{"filter_modality\nset?"}
    Filter -->|yes| QFilter["qdrant.models.Filter(\n  must=[FieldCondition(\n    key='modality',\n    match=MatchValue(value)\n  )]\n)"]
    Filter -->|no| Deser

    QFilter --> Deser["deserialize payload\n→ list[dict] with all\nChunk fields + qdrant score"]

    Deser --> Return["return list[dict]\nready for reranker or\ndirect ChunkResult conversion"]
```
