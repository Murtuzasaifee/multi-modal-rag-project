# Parsing Pipeline

`DocumentParser.parse_file()` wraps the GLM-OCR SDK and branches on `PARSER_BACKEND`. The cloud path must explicitly pass `start_page_id=0, end_page_id=N-1` — without them the SDK silently parses only page 1. The Ollama path ignores that range parameter and handles pages internally via pypdfium2. Both paths produce an identical `ParseResult` downstream.

```mermaid
flowchart TD
    Input["PDF / Image\nfile_path"] --> BackendCheck{PARSER_BACKEND}

    BackendCheck -->|cloud| CloudInit["GlmOcr(\n  api_key=z_ai_api_key\n)\nno config_path"]
    BackendCheck -->|ollama| OllamaInit["GlmOcr(\n  config_path='ollama/config.yaml'\n)\nno api_key — passing api_key\nforces cloud even with config_path"]

    CloudInit --> PageCount["count_pdf_pages(file_path)\nvia PyMuPDF (fitz)\n→ N pages"]
    PageCount --> CloudParse["_parser.parse(\n  str(file_path),\n  start_page_id=0,\n  end_page_id=N-1\n)"]

    OllamaInit --> OllamaParse["_parser.parse(str(file_path))\npypdfium2 handles page loading\nstart/end params ignored by SDK\nsave_layout_visualization=False\n(avoids numpy/Queue SDK bugs)"]

    CloudParse & OllamaParse --> SDKOut["PipelineResult\n.json_result: list[list[dict]]\n  each elem: {index, label,\n  content, bbox_2d [, polygon]}\n.markdown_result: str\n(full document markdown)"]

    SDKOut --> FromSDK["ParseResult.from_sdk_result\n(raw, source_file)"]

    FromSDK --> PerPage["for page_idx, page_elems\nin enumerate(raw.json_result)"]

    PerPage --> CreateElem["ParsedElement(\n  label   = elem['label'],\n  text    = elem['content'],\n  bbox    = elem['bbox_2d'],\n  score   = elem.get('score', 1.0),\n  reading_order = elem['index']\n)"]

    CreateElem --> AssembleMD["assemble_markdown(elements)\n① sort by reading_order\n② apply PROMPT_MAP:\n   document_title  → # title\n   paragraph_title → ## title\n   table/formula   → as-is\n   code_block      → ``` block\n③ skip: image, seal, page_number\n④ join with double newline"]

    AssembleMD --> PageRes["PageResult(\n  page_num = page_idx + 1,\n  elements = [ParsedElement ...],\n  markdown = assembled_md\n)"]

    PageRes --> FinalResult["ParseResult(\n  source_file = str(file_path),\n  pages = [PageResult ...],\n  total_elements = Σ len(page.elements),\n  full_markdown = raw.markdown_result\n)"]
```
