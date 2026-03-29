# Cloud vs Ollama Parsing Paths

`PARSER_BACKEND` selects between two execution paths for the same GLM-OCR + PP-DocLayout-V3 stack. The cloud path sends documents to Z.AI's MaaS GPU and requires an explicit page range (a critical SDK footgun: without `start_page_id`/`end_page_id` the SDK silently parses only page 1). The Ollama path pulls the `glm-ocr:latest` model (600 MB) locally; the page range parameters are silently ignored as pypdfium2 handles loading. Both paths produce structurally identical `PipelineResult` objects — downstream processing is shared.

```mermaid
flowchart LR
    subgraph Cloud["PARSER_BACKEND = cloud"]
        CI["GlmOcr(\n  api_key=z_ai_api_key\n)\nno config_path"]
        CI --> CPC["count_pdf_pages(file_path)\nvia PyMuPDF  fitz\n→ N pages\n⚠ REQUIRED — omitting\nstart/end silently\nparses only page 1"]
        CPC --> CParse["_parser.parse(\n  str(file_path),\n  start_page_id=0,\n  end_page_id=N-1\n)"]
        CParse --> CNet["HTTPS to Z.AI\nGLM-OCR 0.9B on remote GPU\nPP-DocLayout-V3 (23 labels)"]
        CNet --> COut["PipelineResult\njson_result: list[list[dict]]\n  keys: index, label,\n        content, bbox_2d\n  (no polygon field)\nmarkdown_result: str"]
        CProps["Requires: Z_AI_API_KEY\nLatency: ~2–5s / page\nData leaves your machine\nNo GPU needed locally"]
    end

    subgraph Ollama["PARSER_BACKEND = ollama"]
        OI["GlmOcr(\n  config_path='ollama/config.yaml'\n)\n⚠ no api_key — passing\napi_key forces cloud mode\neven with config_path"]
        OI --> OConf["ollama/config.yaml:\n  ocr_api.api_host: localhost\n  ocr_api.api_port: 11434\n  ocr_api.api_mode: ollama_generate\n  model: glm-ocr:latest\n  enable_layout: true\n  maas.enabled: false"]
        OConf --> OParse["_parser.parse(str(file_path))\nstart/end page params ignored\npypdfium2 handles page loading\nsave_layout_visualization=False\n(avoids numpy/Queue SDK bugs)"]
        OParse --> OLocal["local Ollama server\nollama serve  +\nollama pull glm-ocr:latest\n600 MB model download"]
        OLocal --> OOut["PipelineResult\njson_result: list[list[dict]]\n  keys: index, label,\n        content, bbox_2d,\n        polygon  ← extra field\nmarkdown_result: str"]
        OProps["Requires: ollama serve + model\nLatency: ~5–30s / page (CPU)\nFully offline · private\ninstall extra: uv pip install -e '.[layout]'"]
    end

    COut & OOut --> Shared["ParseResult.from_sdk_result(raw, source_file)\nIdentical processing from here:\ndocument_aware_chunking()\nenrich_chunks()  →  embed_chunks()  →  Qdrant upsert"]
```
