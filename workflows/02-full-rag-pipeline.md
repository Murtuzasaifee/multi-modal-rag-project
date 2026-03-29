# Full RAG Pipeline (End-to-End Sequence)

A complete trace of a `POST /generate` request from the user's question to the final answer. The API embeds the query twice (dense + sparse), runs hybrid retrieval via Qdrant's RRF fusion, reranks the candidates, assembles a context string from the top-n chunks, and calls GPT-4o — returning the answer together with its source chunks and latency.

```mermaid
sequenceDiagram
    actor User
    participant API as FastAPI /generate
    participant Embedder as BaseEmbedder
    participant Store as QdrantDocumentStore
    participant Reranker as BaseReranker
    participant LLM as GPT-4o

    User->>API: POST /generate\n{query, top_k, top_n, rerank, max_tokens}

    API->>Embedder: embed([query_text])
    Embedder-->>API: query_dense  [3072-dim float]

    API->>API: compute_sparse_vectors([query_text])\n→ query_sparse  SparseVector

    API->>Store: query_points(\n  Prefetch(text_dense) + Prefetch(bm25_sparse),\n  FusionQuery(RRF), limit=top_k\n)
    Store-->>API: top_k candidate dicts (payloads)

    alt rerank == True
        API->>Reranker: rerank(query, candidates, top_n)
        Reranker-->>API: top_n dicts sorted by rerank_score DESC
    else rerank == False
        API->>API: candidates[:top_n], rerank_score=None
    end

    API->>API: build context string\nfor each chunk: "[page N] " + chunk.text\n(tables: text=summary, caption=markdown)

    API->>LLM: chat.completions.create(\n  model=gpt-4o,\n  messages=[system, user+context+query],\n  max_tokens, temperature=0.0\n)
    LLM-->>API: answer text

    API-->>User: GenerateResponse\n{query, answer, sources: [ChunkResult], latency_ms}
```
