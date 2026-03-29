# System Overview

The pipeline has four sequential phases. Phase 1 (Parse) converts raw documents into structured elements using GLM-OCR and PP-DocLayout-V3. Phase 2 (Ingest) chunks, enriches, embeds, and stores those elements in Qdrant. Phase 3 (Retrieve) runs hybrid dense+sparse search with optional reranking. Phase 4 (Generate) builds a context string from retrieved chunks and calls GPT-4o.

```mermaid
flowchart TD
    subgraph Phase1["Phase 1 — Parse"]
        PDF["PDF / Image\n(file_path)"] --> Parser["DocumentParser\n.parse_file()"]
        Parser --> OCR["GLM-OCR SDK\n+ PP-DocLayout-V3\n23 element categories"]
        OCR --> ParseResult["ParseResult\n(pages, elements, full_markdown)"]
    end

    subgraph Phase2["Phase 2 — Ingest"]
        ParseResult --> Chunker["document_aware_chunking()\nlist[Chunk]"]
        Chunker --> Enricher["enrich_chunks()\nGPT-4o vision / JSON mode"]
        Enricher --> Embedder["embed_chunks()\ndense + sparse vectors"]
        Embedder --> Qdrant[("Qdrant\ntext_dense · bm25_sparse")]
    end

    subgraph Phase3["Phase 3 — Retrieve"]
        Query["User Query"] --> HybridSearch["store.search()\nRRF Fusion"]
        Qdrant --> HybridSearch
        HybridSearch --> Reranker["reranker.rerank()\ntop-n ChunkResults"]
    end

    subgraph Phase4["Phase 4 — Generate"]
        Reranker --> ContextBuilder["Build context string\n[page N] chunk.text ..."]
        ContextBuilder --> GPT4o["GPT-4o\nchat.completions.create()"]
        GPT4o --> Answer["LLM Answer\n+ source chunks"]
    end

    Phase1 --> Phase2
    Phase2 -. "persisted" .-> Phase3
    Phase3 --> Phase4
```
