# Multimodal Chunk Enrichment

`enrich_chunks()` runs after chunking and mutates chunks in-place. Each modality has a dedicated async handler. Image chunks are cropped from the PDF using PyMuPDF, encoded as base64 PNG, and described by GPT-4o vision. Table chunks are sent to GPT-4o in JSON mode, producing both a full markdown table (stored in `caption` for LLM generation) and a semantic summary (stored in `text` for embedding). Formula and algorithm chunks get verbal descriptions. Text chunks are unchanged.

```mermaid
flowchart LR
    In["list[Chunk]\nfrom document_aware_chunking()"] --> Dispatch["enrich_chunks(\n  chunks, pdf_path, client,\n  model='gpt-4o',\n  max_concurrent=5\n)\nasyncio.Semaphore controls\nconcurrency across all calls"]

    Dispatch --> |"modality == 'image'"| ImgPath
    Dispatch --> |"modality == 'table'"| TblPath
    Dispatch --> |"modality == 'formula'"| FmlPath
    Dispatch --> |"modality == 'algorithm'"| AlgPath
    Dispatch --> |"modality == 'text'"| TxtPass["pass-through\nno API call"]

    subgraph ImgPath["_enrich_image_single()"]
        CropPDF["fitz.open(pdf_path)\npage.get_pixmap(matrix=2x)\n→ render at 2× DPI\ncrop to chunk.bbox\n(normalized 0–1 → pixels)"]
        EncB64["Pillow → PNG bytes\nbase64.b64encode()\n→ data:image/png;base64,..."]
        VisionCall["GPT-4o vision\nprompt: describe as\nTYPE / CAPTION /\nDETAIL / STRUCTURE\nsections"]
        ParseImg["_parse_image_response(text)\n→ (short_caption, full_description)"]
        SetImg["chunk.image_base64 = b64_str\nchunk.caption = full_description\nchunk.text = short_caption\n(short caption used for embedding)"]
        CropPDF --> EncB64 --> VisionCall --> ParseImg --> SetImg
    end

    subgraph TblPath["_enrich_table_single()"]
        TblCall["GPT-4o JSON mode\ninput: raw OCR text/HTML table\nprompt: reproduce as\nmarkdown table + semantic summary"]
        ParseTbl["_parse_table_json_response(\n  raw_ocr, json_str\n)\n→ (caption=markdown_table,\n   text=semantic_summary)"]
        SetTbl["chunk.caption = markdown_table\n  → used in /generate context\nchunk.text = semantic_summary\n  → embedded for retrieval"]
        TblCall --> ParseTbl --> SetTbl
    end

    subgraph FmlPath["_enrich_formula_single()"]
        FmlCall["GPT-4o text\nprompt: verbally describe\nthis mathematical formula\nin plain language"]
        SetFml["chunk.text = verbal_description"]
        FmlCall --> SetFml
    end

    subgraph AlgPath["_enrich_algorithm_single()"]
        AlgCall["GPT-4o text\nprompt: describe the\nalgorithm's purpose and steps\nsemanticaly"]
        SetAlg["chunk.text = semantic_description"]
        AlgCall --> SetAlg
    end

    SetImg & SetTbl & SetFml & SetAlg & TxtPass --> Out["Enriched list[Chunk]\nReady for embed_chunks()"]
```
