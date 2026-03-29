# Reranking Backends

`get_reranker(settings)` is a factory keyed on `RERANKER_BACKEND`. All four backends implement `BaseReranker.rerank(query, candidates, top_n) → list[dict]`, adding a `rerank_score` key to each candidate dict and returning them sorted descending. The two cloud backends (OpenAI, Jina) and the two local backends (BGE, Qwen VL) differ in latency, cost, and whether they can score image chunks visually.

```mermaid
flowchart TD
    In["query: str\ncandidates: list[dict]\ntop_n: int"] --> Factory["get_reranker(settings)\nRERANKER_BACKEND env var"]

    Factory -->|openai| OAI["OpenAIReranker\nmodel: gpt-4o-mini\ncloud · multimodal"]
    Factory -->|jina| Jina["JinaReranker\nmodel: jina-reranker-m0\ncloud · multimodal"]
    Factory -->|bge| BGE["BGEReranker\nbge-reranker-v2-minicpm-layerwise\nlocal · text-only · fast"]
    Factory -->|qwen| Qwen["QwenVLReranker\nQwen3-VL-Reranker-2B\nlocal · multimodal · slow"]

    subgraph OAIBlock["OpenAIReranker — _score_one() × N via asyncio.gather"]
        OAITxt["text chunk:\nmessages=[{role:user,\n  content: query + chunk.text}]"]
        OAIImg["image chunk (image_base64 set):\nmessages=[{role:user,\n  content:[\n    {type:text, text:query},\n    {type:image_url,\n     image_url:{url:data:image/png;base64,...}}\n  ]}]"]
        OAICall["chat.completions.create\n(gpt-4o-mini)\n→ parse float from response\ncost: ~$0.03–0.10 / 20 candidates"]
        OAITxt & OAIImg --> OAICall
    end

    subgraph JinaBlock["JinaReranker — single batch API call"]
        JinaReq["POST https://api.jina.ai/v1/rerank\n{\n  model: jina-reranker-m0,\n  query: query_text,\n  documents: [text or image content]\n}"]
        JinaResp["response.results[i].relevance_score\n→ rerank_score\ncost: ~$0.01–0.02 / 20 candidates"]
        JinaReq --> JinaResp
    end

    subgraph BGEBlock["BGEReranker — run_in_executor (sync, thread pool)"]
        BGEIn["image chunks → use chunk.caption\n(text description, no vision)"]
        BGEModel["LayerWiseFlagLLMReranker\ndevice: MPS (Apple Silicon)\nor CPU fallback\n~50–100ms / 20 candidates"]
        BGEIn --> BGEModel
    end

    subgraph QwenBlock["QwenVLReranker — run_in_executor (sync, thread pool)"]
        QwenIn["image chunks → pass image_base64\ntext chunks → pass chunk.text"]
        QwenModel["Qwen3-VL-Reranker-2B\ntransformers + torch\ndevice: MPS or CPU\n~400–800ms / 20 candidates"]
        QwenIn --> QwenModel
    end

    OAI --> OAIBlock
    Jina --> JinaBlock
    BGE --> BGEBlock
    Qwen --> QwenBlock

    OAICall & JinaResp & BGEModel & QwenModel --> Sort["Sort all candidates by\nrerank_score DESC\nreturn top_n list[dict]\nwith 'rerank_score' key added"]
```
