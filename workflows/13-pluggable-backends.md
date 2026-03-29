# Pluggable Backends (Strategy Pattern)

All runtime behaviour is controlled by three env vars read at startup by `get_settings()` (pydantic-settings singleton). Each axis is a classic strategy pattern: a factory function reads the config and returns the appropriate concrete implementation, all of which satisfy the same abstract interface. This means adding a new embedding provider or reranker requires only: a new subclass, a new key in the factory dict, and a new env-var value — no changes to callers.

```mermaid
flowchart TD
    Env[".env\nPARSER_BACKEND\nEMBEDDING_PROVIDER\nRERANKER_BACKEND\n+ API keys"] --> Cfg["Settings  (pydantic-settings)\nget_settings()  singleton\nloaded once at first call"]

    Cfg --> PF & EF & RF

    subgraph PF["DocumentParser  —  PARSER_BACKEND"]
        PChk{PARSER_BACKEND}
        PChk -->|cloud| CP["GlmOcr(api_key=z_ai_api_key)\nZ.AI MaaS — remote GPU\nRequires: Z_AI_API_KEY\nLatency: ~2–5s/page\nData sent to Z.AI"]
        PChk -->|ollama| OP["GlmOcr(config_path='ollama/config.yaml')\nlocal glm-ocr:latest  600 MB\nRequires: ollama serve\nLatency: ~5–30s/page (CPU)\nFully offline / private"]
    end

    subgraph EF["get_embedder(settings)  —  EMBEDDING_PROVIDER"]
        EChk{EMBEDDING_PROVIDER}
        EChk -->|openai| OE["OpenAIEmbedder\ntext-embedding-3-large\ndimensions=3072\nbatch_size=100\nRequires: OPENAI_API_KEY"]
        EChk -->|gemini| GE["GeminiEmbedder\ngoogle.genai\nrun_in_executor (sync → async)\nRequires: GEMINI_API_KEY"]
    end

    subgraph RF["get_reranker(settings)  —  RERANKER_BACKEND"]
        RChk{RERANKER_BACKEND}
        RChk -->|openai| OR["OpenAIReranker\ngpt-4o-mini\nMultimodal: ✓  (vision)\nCloud API\nRequires: OPENAI_API_KEY"]
        RChk -->|jina| JR["JinaReranker\njina-reranker-m0\nMultimodal: ✓\nCloud API\nRequires: JINA_API_KEY"]
        RChk -->|bge| BR["BGEReranker\nbge-reranker-v2-minicpm-layerwise\nMultimodal: ✗  (caption text only)\nLocal  —  install: uv pip install -e '.[bge]'\nDevice: MPS or CPU"]
        RChk -->|qwen| QR["QwenVLReranker\nQwen3-VL-Reranker-2B\nMultimodal: ✓  (image_base64)\nLocal  —  install: uv pip install -e '.[qwen]'\nDevice: MPS or CPU"]
    end
```
