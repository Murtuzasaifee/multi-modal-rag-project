# Data Structures

The core data types that flow through the pipeline. `ParsedElement` is the atomic OCR output per element. `PageResult` aggregates elements per page. `ParseResult` wraps the entire document. `Chunk` is the RAG unit after chunking and enrichment. `QdrantPoint` is what gets stored. `ChunkResult` is the API response model returned to callers.

```mermaid
classDiagram
    class ParsedElement {
        +label: str
        +text: str
        +bbox: list[float]
        +score: float
        +reading_order: int
    }

    class PageResult {
        +page_num: int
        +elements: list[ParsedElement]
        +markdown: str
    }

    class ParseResult {
        +source_file: str
        +pages: list[PageResult]
        +total_elements: int
        +full_markdown: str
        +from_sdk_result(raw, source_file)$ ParseResult
    }

    class Chunk {
        +text: str
        +chunk_id: str
        +page: int
        +element_types: list[str]
        +bbox: list[float]
        +source_file: str
        +is_atomic: bool
        +modality: str
        +image_base64: str
        +caption: str
    }

    class QdrantPoint {
        +id: UUID5
        +text_dense: list[float]
        +bm25_sparse: SparseVector
        +payload: ChunkFields
    }

    class SparseVector {
        +indices: list[int]
        +values: list[float]
    }

    class ChunkResult {
        +chunk_id: str
        +text: str
        +source_file: str
        +page: int
        +modality: str
        +element_types: list[str]
        +bbox: list[float]
        +is_atomic: bool
        +caption: str
        +rerank_score: float
        +image_base64: str
    }

    PageResult "1" --> "*" ParsedElement : contains
    ParseResult "1" --> "*" PageResult : contains
    ParseResult ..> Chunk : chunked via document_aware_chunking()
    Chunk ..> QdrantPoint : embedded via embed_chunks()
    QdrantPoint --> SparseVector : bm25_sparse
    QdrantPoint ..> ChunkResult : deserialized on search()
```
