# Ingestion Pipeline

Triggered by `POST /ingest` or `scripts/ingest.py`. A single document travels through five stages: synchronous parsing (offloaded to a thread executor in async contexts), structure-aware chunking, per-modality GPT-4o enrichment (controlled by `asyncio.Semaphore`), dual dense+sparse embedding, and batched upsert to Qdrant.

```mermaid
flowchart LR
    PDF["PDF / Image\nfile_path"] --> Parser["DocumentParser\n.parse_file()\nsync — offloaded via\nrun_in_executor()"]

    Parser --> ParseResult["ParseResult\nsource_file\npages: list[PageResult]\nfull_markdown: str"]

    ParseResult --> Chunker["document_aware_chunking\n(pages, source_file,\nmax_chunk_tokens=512)\n→ list[Chunk]"]

    Chunker --> Enrich["enrich_chunks()\nasyncio.Semaphore\nmax_concurrent=5"]

    Enrich --> |"modality=image"| GPT4oVision["GPT-4o vision\ncrop bbox → base64 PNG\n→ TYPE / CAPTION /\nDETAIL / STRUCTURE"]
    Enrich --> |"modality=table"| GPT4oJSON["GPT-4o JSON mode\nraw HTML table\n→ markdown table\n+ semantic summary"]
    Enrich --> |"modality=formula\nor algorithm"| GPT4oText["GPT-4o text\n→ verbal / semantic\ndescription"]
    Enrich --> |"modality=text"| Pass["unchanged"]

    GPT4oVision & GPT4oJSON & GPT4oText & Pass --> Enriched["Enriched list[Chunk]\nchunk.text = embed text\nchunk.caption = gen text\nchunk.image_base64 = PNG"]

    Enriched --> EmbedChunks["embed_chunks(\n  chunks, embedder, settings\n)"]

    EmbedChunks --> |dense| Dense["embedder.embed(texts)\nbatch_size=100\nOpenAI or Gemini\n→ list[list[float]] 3072-dim"]
    EmbedChunks --> |sparse| Sparse["compute_sparse_vectors\nTF feature-hashing\n2¹⁷ = 131072 buckets\n→ list[SparseVector]"]

    Dense & Sparse --> Upsert["store.upsert_chunks(\n  chunks, dense, sparse\n  batch_size=64\n)\nid = UUID5(chunk_id)"]

    Upsert --> Qdrant[("Qdrant\ntext_dense: 3072-dim COSINE\nbm25_sparse: sparse TF")]
```
