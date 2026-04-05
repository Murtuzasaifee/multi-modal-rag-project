# Testing Guide

This file documents all commands used to test the multi-modal RAG pipeline end-to-end.

> **Important:** Always use `uv run` to run Python scripts. Never call `python` directly, as it will not pick up the virtual environment packages.

---

## Prerequisites

### 1. Install dependencies

```bash
uv venv --python 3.12
source .venv/bin/activate
uv pip install -e ".[dev]"
```

### 2. Configure environment

Copy the example env file and fill in your API keys:

```bash
cp .env.example .env
```

Required keys in `.env`:

```dotenv
Z_AI_API_KEY=...          # GLM-OCR MaaS API (Z.AI cloud)
OPENAI_API_KEY=sk-...     # OpenAI (captioning + embeddings + reranking)
```

Optional (pick a reranker backend):

```dotenv
RERANKER_BACKEND=jina     # or: openai | bge | qwen
JINA_API_KEY=...          # required if RERANKER_BACKEND=jina
```

### 3. Start Qdrant (Docker)

```bash
docker compose up -d qdrant
```

Verify it is running:

```bash
curl http://localhost:6333
```

### 4. Prepare a test document

The Z.AI API works best with real PDF documents. To extract a single page from a larger PDF (avoids upload timeouts on large files):

```bash
uv run python - <<'EOF'
import fitz
doc = fitz.open("docling_report.pdf")
new = fitz.open()
new.insert_pdf(doc, from_page=0, to_page=0)
new.save("data/raw/test_page1.pdf")
print("Saved data/raw/test_page1.pdf")
EOF
```

---

## Section 1 — CLI Scripts

All scripts live in `scripts/`. Each script adds `src/` to `sys.path` automatically, so no `PYTHONPATH` export is needed.

---

### `scripts/parse.py` — Parse a document

Sends a document to the GLM-OCR MaaS API and saves the output locally.

**Parse a PDF and save both Markdown and JSON output:**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf
```

**Parse and also produce RAG-ready chunks JSON:**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf --chunks
```

**Parse and write output to a custom directory:**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf --output ./output/ --chunks
```

**Parse only to Markdown (skip JSON):**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf --format markdown
```

**Parse only to JSON:**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf --format json
```

**Parse an entire directory of documents:**

```bash
uv run python scripts/parse.py ./data/raw/ --output ./output/ --chunks
```

**Parse an image file:**

```bash
uv run python scripts/parse.py data/raw/figure.png --chunks
```

**Increase log verbosity:**

```bash
uv run python scripts/parse.py data/raw/test_page1.pdf --log-level DEBUG
```

**Expected output (success):**

```
doc-parser — processing 1 file(s) → output
  Parsing test_page1.pdf... ✓ 1 page(s), 10 elements
  Saved 2 chunks to output/test_page1_chunks.json

Done! Output saved to output
```

---

### `scripts/ingest.py` — Ingest a document into Qdrant

Parses a document, captions image chunks (GPT-4o), embeds all chunks, and upserts them into the Qdrant vector store.

**Ingest a single PDF:**

```bash
uv run python scripts/ingest.py data/raw/test_page1.pdf
```

**Ingest and recreate the collection first (wipes existing data):**

```bash
uv run python scripts/ingest.py data/raw/test_page1.pdf --overwrite
```

**Ingest an image file:**

```bash
uv run python scripts/ingest.py data/raw/figure.png
```

**Ingest an entire directory:**

```bash
uv run python scripts/ingest.py data/raw/
```

**Ingest into a specific collection:**

```bash
uv run python scripts/ingest.py data/raw/test_page1.pdf --collection my_collection
```

**Skip image captioning (faster, lower cost):**

```bash
uv run python scripts/ingest.py data/raw/test_page1.pdf --no-caption
```

**Expected output (success):**

```
GLM-OCR initialized in MaaS mode (cloud API passthrough)
...
Ingestion complete
  Collection : documents
  Files      : 1
  image      : 1 chunks
  text       : 1 chunks
  Total      : 2 chunks
```

---

### `scripts/search.py` — Query the vector store

Embeds the query, runs hybrid retrieval from Qdrant, then re-ranks results with the configured backend.

**Basic search:**

```bash
uv run python scripts/search.py "document layout detection"
```

**Search and skip re-ranking (raw retrieval results):**

```bash
uv run python scripts/search.py "document layout detection" --no-rerank
```

**Retrieve more candidates before re-ranking:**

```bash
uv run python scripts/search.py "document layout detection" --top-k 20
```

**Limit the number of final results after re-ranking:**

```bash
uv run python scripts/search.py "document layout detection" --top-k 20 --top-n 5
```

**Filter by modality (only return image chunks):**

```bash
uv run python scripts/search.py "figure showing accuracy vs recall" --filter-modality image
```

**Filter by modality (text only):**

```bash
uv run python scripts/search.py "transformer attention mechanism" --filter-modality text
```

**Override re-ranker backend at runtime:**

```bash
uv run python scripts/search.py "query" --backend openai
uv run python scripts/search.py "query" --backend jina
uv run python scripts/search.py "query" --backend bge
```

**Query a specific collection:**

```bash
uv run python scripts/search.py "query" --collection my_collection
```

**Expected output (success):**

```
Query: document layout detection
Collection: documents | top-k: 20 | modality filter: all

Retrieved 2 candidates.
Re-ranking with backend: jina
┏━━━┳━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ # ┃ Score    ┃ Modality   ┃ Source               ┃ Page  ┃ Text            ┃
┡━━━╇━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━━━━━━┩
│ 1 │ 0.8781   │ text       │ test_page1.pdf       │ 1     │ # Docling ...   │
│ 2 │ 0.5560   │ image      │ test_page1.pdf       │ 1     │ [IMAGE] A duck… │
└───┴──────────┴────────────┴──────────────────────┴───────┴─────────────────┘
```

---

### Unit tests

Run all unit tests (no API keys or Qdrant required):

```bash
uv run pytest tests/unit/ -v
```

Run a single test file:

```bash
uv run pytest tests/unit/test_embedder.py -v
```

Run a single test class:

```bash
uv run pytest tests/unit/test_embedder.py::TestOpenAIEmbedder -v
```

Run a single test function:

```bash
uv run pytest tests/unit/test_embedder.py::TestOpenAIEmbedder::test_embed_delegates -v
```

---

## Section 2 — FastAPI Application

### Start the API server

```bash
uv run uvicorn doc_parser.api.app:app --host 0.0.0.0 --port 8000
```

**With auto-reload (development mode):**

```bash
uv run uvicorn doc_parser.api.app:app --host 0.0.0.0 --port 8000 --reload
```

**Using the convenience script:**

```bash
uv run python scripts/serve.py --reload
```

The interactive API docs are available at:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

---

### `GET /health` — Health check

Pings Qdrant and OpenAI to verify connectivity.

```bash
curl http://localhost:8000/health
```

**Expected response:**

```json
{
    "status": "ok",
    "qdrant": "ok",
    "openai": "ok",
    "reranker_backend": "jina"
}
```

**Possible statuses:** `"ok"` | `"degraded"` (if Qdrant or OpenAI is unreachable).

---

### `GET /collections` — List collections

Lists all Qdrant collection names.

```bash
curl http://localhost:8000/collections
```

**Expected response:**

```json
{
    "collections": ["documents"]
}
```

---

### `POST /ingest` — Ingest by file path

Ingest a document that already exists on the server's filesystem by providing its path.

**Basic ingest:**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/test_page1.pdf"}'
```

**Ingest and overwrite the collection (wipes existing data):**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/test_page1.pdf", "overwrite": true}'
```

**Ingest into a custom collection:**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/test_page1.pdf", "collection": "my_collection"}'
```

**Ingest with a custom chunk size:**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/test_page1.pdf", "max_chunk_tokens": 256}'
```

**Ingest without image captioning:**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/test_page1.pdf", "caption": false}'
```

**Ingest an image file:**

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"file_path": "data/raw/figure.png"}'
```

**Full request body schema:**

```json
{
    "file_path": "data/raw/test_page1.pdf",
    "collection": null,
    "overwrite": false,
    "max_chunk_tokens": 512,
    "caption": true
}
```

**Expected response:**

```json
{
    "source_file": "data/raw/test_page1.pdf",
    "collection": "documents",
    "chunks_upserted": 2,
    "modality_counts": {"text": 1, "image": 1},
    "latency_ms": 8779.95
}
```

---

### `POST /ingest/file` — Ingest via file upload

Upload a document directly from your local machine as a multipart form upload.

**Upload a PDF:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/test_page1.pdf"
```

**Upload a PDF and overwrite the collection:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/test_page1.pdf" \
  -F "overwrite=true"
```

**Upload into a custom collection:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/test_page1.pdf" \
  -F "collection=my_collection"
```

**Upload with a custom chunk size:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/test_page1.pdf" \
  -F "max_chunk_tokens=256"
```

**Upload without image captioning:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/test_page1.pdf" \
  -F "caption=false"
```

**Upload an image file (PNG, JPG, TIFF, BMP):**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@data/raw/figure.png"
```

**Supported file types:** `.pdf`, `.png`, `.jpg`, `.jpeg`, `.tiff`, `.bmp`

**Expected response:**

```json
{
    "source_file": "/tmp/tmpXXXXXX.pdf",
    "collection": "documents",
    "chunks_upserted": 2,
    "modality_counts": {"text": 1, "image": 1},
    "latency_ms": 19569.54
}
```

**Error — unsupported file type:**

```bash
curl -X POST http://localhost:8000/ingest/file \
  -F "file=@document.docx"
# → 400 Bad Request
# {"detail": "Unsupported file type '.docx'. Supported: ['.bmp', '.jpeg', '.jpg', '.pdf', '.png', '.tiff']"}
```

---

### `POST /search` — Search the vector store

Embeds the query, retrieves candidates from Qdrant (hybrid dense + sparse), and re-ranks results.

**Basic search:**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "document layout detection"}'
```

**Search with more candidates and fewer final results:**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "document layout detection", "top_k": 20, "top_n": 5}'
```

**Search without re-ranking:**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "document layout detection", "rerank": false}'
```

**Filter by modality (image chunks only):**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "figure showing accuracy vs recall", "filter_modality": "image"}'
```

**Filter by modality (text only):**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "transformer attention mechanism", "filter_modality": "text"}'
```

**Search a specific collection:**

```bash
curl -X POST http://localhost:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query": "document layout detection", "collection": "my_collection"}'
```

**Full request body schema:**

```json
{
    "query": "document layout detection",
    "top_k": 20,
    "top_n": null,
    "rerank": true,
    "filter_modality": null,
    "collection": null
}
```

**Allowed `filter_modality` values:** `"text"` | `"image"` | `"table"` | `"formula"` | `null` (all)

**Expected response:**

```json
{
    "query": "document layout detection",
    "backend": "jina",
    "total_candidates": 2,
    "results": [
        {
            "chunk_id": "test_page1.pdf_1_1",
            "text": "# Docling Technical Report ...",
            "source_file": "test_page1.pdf",
            "page": 1,
            "modality": "text",
            "element_types": ["text", "text", "..."],
            "bbox": null,
            "is_atomic": false,
            "caption": null,
            "rerank_score": 0.8713,
            "image_base64": null
        }
    ]
}
```

---

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `ModuleNotFoundError: No module named 'rich'` | Running `python` instead of `uv run python` | Always prefix with `uv run` |
| `write operation timed out` | Large PDF upload to Z.AI API over slow connection | Extract a single page first (see Prerequisites) |
| `Connection refused` on port 6333 | Qdrant Docker container not running | `docker compose up -d qdrant` |
| `'Settings' object has no attribute 'openai_embedding_model'` | Stale code using old field name | Field was renamed to `embedding_model` in Phase 5 |
| `UserWarning: Qdrant client version X.Y.Z is incompatible` | Minor version mismatch between client and server | Safe to ignore; use `check_compatibility=False` to suppress |
| `400 Unsupported file type` | Uploading an unsupported format | Use `.pdf`, `.png`, `.jpg`, `.jpeg`, `.tiff`, or `.bmp` |
