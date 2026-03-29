# Embedding Architecture

`embed_chunks()` produces two parallel representations per chunk. The dense path calls either `OpenAIEmbedder` (batched `embeddings.create`, max 100 texts per call) or `GeminiEmbedder` (sync SDK offloaded via `run_in_executor`). The sparse path runs entirely locally: tokenize → term-frequency count → feature-hash into 2¹⁷ = 131,072 buckets → normalize — no vocabulary, no external API. Both are returned as a tuple and zipped with chunks to build `PointStruct` objects for Qdrant.

```mermaid
flowchart TD
    Chunks["list[Chunk]"] --> Extract["texts = [chunk.text for chunk in chunks]\n(empty strings → '[empty]' guard)"]

    Extract --> Dense & Sparse

    subgraph Dense["Dense Path — embedder.embed(texts)"]
        ProvChk{EMBEDDING_PROVIDER}

        ProvChk -->|openai| OAIBatch["OpenAIEmbedder\nclient.embeddings.create(\n  model='text-embedding-3-large',\n  dimensions=3072,\n  input=batch  ← split at 100\n)\nbatch loop → gather results\nin input order"]

        ProvChk -->|gemini| GemBatch["GeminiEmbedder\nloop.run_in_executor(\n  None,\n  self._embed_sync,\n  texts\n)\ngoogle.genai client\nrunning in thread pool"]

        OAIBatch & GemBatch --> DenseOut["list[list[float]]\nshape: [N, 3072]"]
    end

    subgraph Sparse["Sparse Path — compute_sparse_vectors(texts)"]
        Tok["tokenize:\ntext.lower()\nre.findall(r'[a-z0-9]+', text)"]
        TF["Counter(tokens)\n→ {term: count}"]
        Hash["abs(hash(term)) % 2¹⁷\n→ bucket index  [0, 131071]\nno vocabulary needed\nstreaming-friendly"]
        Norm["values[term] =\ncount[term] / total_tokens\n(normalized TF)"]
        Sort["sort by index ASC\nSparseVector(\n  indices=[...],\n  values=[...]\n)"]
        Tok --> TF --> Hash --> Norm --> Sort --> SparseOut["list[SparseVector]\nshape: [N, sparse]"]
    end

    DenseOut & SparseOut --> Zip["zip(chunks, dense_embeddings, sparse_vectors)\n→ PointStruct per chunk\nid = UUID5(NAMESPACE_DNS, chunk.chunk_id)\nvector = {\n  'text_dense': dense,\n  'bm25_sparse': sparse\n}\npayload = chunk fields"]

    Zip --> Upsert["store.upsert_chunks()\nbatch_size=64\nAsyncQdrantClient.upsert()"]
```
