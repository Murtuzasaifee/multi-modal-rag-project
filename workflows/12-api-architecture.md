# API Architecture

`create_app()` builds the FastAPI application with a lifespan context manager (loguru setup), `LoggingMiddleware` (adds `X-Request-Id` header per request), and four route groups. All heavy dependencies — OpenAI client, Qdrant store, embedder, reranker — are created once per process via `@lru_cache` singleton factories in `dependencies.py`. The `get_openai_client()` dep is kept separate from `get_embedder_dep()` because captioning always needs OpenAI regardless of the configured embedding provider.

```mermaid
flowchart LR
    Client["HTTP Client"] -->|request| LogMW["LoggingMiddleware\nattaches X-Request-Id header\n8-char UUID prefix\nto every response"]

    LogMW --> Router["FastAPI Router"]

    Router --> Health["GET /health\nstatus: ok\ncollection name + count"]
    Router --> Ingest["POST /ingest\nUploadFile  (multipart)\nPOST /ingest  (JSON path)\nIngestRequest → IngestResponse"]
    Router --> Search["POST /search\nSearchRequest → SearchResponse\n{query, results, backend,\ntotal_candidates, latency_ms}"]
    Router --> Generate["POST /generate\nGenerateRequest → GenerateResponse\n{query, answer, sources, latency_ms}"]

    subgraph Deps["dependencies.py — @lru_cache singletons (one per process)"]
        OAICl["get_openai_client()\nAsyncOpenAI(api_key)\nused by: captioning\n(always OpenAI)"]
        StDep["get_store()\nQdrantDocumentStore(settings)\nAsyncQdrantClient internally"]
        EmbDep["get_embedder_dep()\nget_embedder(settings)\nOpenAIEmbedder or GeminiEmbedder"]
        RerDep["get_reranker_dep()\nget_reranker(settings)\n4 backend options"]
    end

    Ingest -->|"parse→chunk\n→enrich→embed→upsert"| OAICl & StDep & EmbDep
    Search -->|"embed query\n→ hybrid search\n→ rerank"| StDep & EmbDep & RerDep
    Generate -->|"search+rerank\n→ context\n→ GPT-4o"| OAICl & StDep & EmbDep & RerDep

    subgraph Schemas["api/schemas.py — Pydantic models"]
        IReq["IngestRequest\nfile_path: str\ncollection: str | None\noverwrite: bool\nmax_chunk_tokens: int\ncaption: bool"]
        SReq["SearchRequest\nquery: str\ntop_k: int  [1–200]\ntop_n: int | None\nfilter_modality: str | None\nrerank: bool"]
        GReq["GenerateRequest\nquery: str\ntop_k, top_n\nfilter_modality\nsystem_prompt: str | None\nmax_tokens: int  [64–4096]"]
        CRes["ChunkResult\nchunk_id, text, source_file\npage, modality, element_types\nbbox, is_atomic, caption\nrerank_score, image_base64"]
    end

    Ingest -.uses.-> IReq
    Search -.uses.-> SReq & CRes
    Generate -.uses.-> GReq & CRes
```
