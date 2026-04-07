# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-Modal RAG Pipeline: a document intelligence system that converts PDFs into Markdown, structured JSON, and RAG-ready chunks using hybrid vector search. 

## Commands

### Setup

```bash
uv venv --python 3.12 && source .venv/bin/activate
uv pip install -e ".[dev]"

# Optional backends
uv pip install -e ".[bge]"     # Local BGE re-ranker
uv pip install -e ".[qwen]"    # Local Qwen VL re-ranker
uv pip install -e ".[gemini]"  # Gemini embeddings
```

### Running

```bash
# Parse PDF → Markdown + JSON + chunks
uv run python scripts/parse.py document.pdf --chunks --output ./output/

# Ingest into Qdrant
uv run python scripts/ingest.py document.pdf

# Search with re-ranking
uv run python scripts/search.py "query" --backend openai

# Start REST API
uv run python scripts/serve.py --host 0.0.0.0 --port 8000 --reload

# Streamlit inspector (cloud)
uv run streamlit run app.py

# Streamlit inspector (local/Ollama)
uv run streamlit run ollama/visualize.py

# Docker multi-service stack
docker-compose up -d
```

### Testing

```bash
# Unit tests (no API keys needed)
uv run pytest tests/unit/ -v

# Single test file
uv run pytest tests/unit/test_reranker.py -v

# With coverage
uv run pytest --cov=src/doc_parser tests/

# Integration tests (requires live credentials + Qdrant)
uv run pytest tests/integration/ -v
```

### Lint & Format

```bash
uv run ruff check src/ tests/ scripts/
uv run ruff check --fix src/ tests/ scripts/
uv run ruff format src/ tests/ scripts/
uv run mypy src/
```

## Architecture

### Pipeline Phases

1. **Parse** (`src/doc_parser/pipeline.py`): Wraps GLM-OCR SDK. PP-DocLayout-V3 detects 23 element categories (titles, tables, formulas, figures, etc.); GLM-OCR 0.9B converts them to text/Markdown. Backend can be cloud (Z.AI) or local (Ollama).

2. **Post-process + Chunk** (`src/doc_parser/post_processor.py`, `chunker.py`): Assembles elements into Markdown preserving reading order. Structure-aware chunking never splits atomic elements (tables, formulas, figures) across chunk boundaries. Outputs Markdown, full element JSON (with bboxes), and RAG chunks JSON.

3. **Ingest** (`src/doc_parser/ingestion/`): Image/table chunks are enriched with GPT captions (`image_captioner.py`). Dense vectors via OpenAI (`text-embedding-3-large`, 3072D) or Gemini; sparse via BM25 feature hashing. Both upserted into Qdrant (`vector_store.py`).

4. **Search** (`src/doc_parser/retrieval/reranker.py`): Hybrid search (dense + sparse + RRF). Four re-ranker backends: `openai` (GPT multimodal), `jina` (cloud API), `bge` (local text), `qwen` (local multimodal).

5. **API** (`src/doc_parser/api/`): FastAPI with routes for `/health`, `/collections`, `/ingest`, `/ingest/file` (multipart), `/search`, `/generate`. Request ID middleware; loguru structured logging.

### Key Design Decisions

- All configuration is validated at startup via Pydantic (`src/doc_parser/config.py`). `get_settings()` is a singleton. It enforces `Z_AI_API_KEY` when `PARSER_BACKEND=cloud` and auto-selects `ollama/config.yaml` for local mode.
- Chunk modalities: `text`, `image`, `table`, `formula`. Images are stored as base64 in Qdrant payloads so re-rankers can access them.
- The FastAPI app uses lifespan for startup/shutdown of shared singletons defined in `src/doc_parser/api/dependencies.py`.
- Unit tests are fully mocked; integration tests require live credentials and a running Qdrant instance.

## Configuration

Copy `.env.example` to `.env`. Key variables:

| Variable | Default | Notes |
|---|---|---|
| `PARSER_BACKEND` | `cloud` | `cloud` or `ollama` |
| `Z_AI_API_KEY` | — | Required when `PARSER_BACKEND=cloud` |
| `OPENAI_API_KEY` | — | Required for captioning, embeddings (openai), re-ranking |
| `EMBEDDING_PROVIDER` | `openai` | `openai` or `gemini` |
| `EMBEDDING_MODEL` | `text-embedding-3-large` | |
| `EMBEDDING_DIMENSIONS` | `3072` | |
| `QDRANT_URL` | `http://localhost:6333` | |
| `QDRANT_COLLECTION_NAME` | `documents` | |
| `RERANKER_BACKEND` | `openai` | `openai`, `jina`, `bge`, `qwen` |
| `IMAGE_CAPTION_ENABLED` | `true` | GPT vision captions for figures/tables |
| `JINA_API_KEY` | — | Required when `RERANKER_BACKEND=jina` |
| `GEMINI_API_KEY` | — | Required when `EMBEDDING_PROVIDER=gemini` |

GLM-OCR SDK configuration lives in `config.yaml` (cloud) or `ollama/config.yaml` (local).
