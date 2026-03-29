# Chunking Architecture

`document_aware_chunking()` is a single-pass state machine over all pages. It maintains three parallel states: **Atomic** (tables, formulas, images — always own chunk, never split), **Title** (pending attachment to the next content element, even across a page boundary), and **Content** (accumulate into a buffer until `max_chunk_tokens` is reached). Token count is estimated as `word_count × 1.3`.

```mermaid
stateDiagram-v2
    [*] --> Init : document_aware_chunking(pages, source_file, max_chunk_tokens=512)

    Init : Flatten all pages into (page_num, element) pairs\nSort by (page_num, reading_order)\nInit accumulators: current_texts=[], current_tokens=0\npending_title=None, chunk_idx=0

    Init --> NextElement

    state NextElement <<choice>>
    NextElement --> AtomicBranch : label ∈ ATOMIC_LABELS\n{table, formula, inline_formula,\n algorithm, image, figure}
    NextElement --> TitleBranch : label ∈ TITLE_LABELS\n{document_title, paragraph_title,\n figure_title}
    NextElement --> ContentBranch : all other labels (paragraph, abstract,\n footnotes, code_block, ...)
    NextElement --> Done : no more elements

    state AtomicBranch {
        [*] --> FlushBuffer : flush current_texts → Chunk\n(if buffer not empty)
        FlushBuffer --> CheckFigTitle : pending_title == 'figure_title'?
        CheckFigTitle --> MergeFigTitle : yes — prepend figure_title\nto atomic element text\nclear pending_title
        CheckFigTitle --> EmitAtomic : no — use element as-is
        MergeFigTitle --> EmitAtomic
        EmitAtomic : Chunk(\n  text=element.text,\n  is_atomic=True,\n  bbox=element.bbox,\n  modality=_infer_modality([label])\n)
    }

    state TitleBranch {
        [*] --> HasContent : current_texts not empty?
        HasContent --> FlushFirst : yes — flush() before storing title
        HasContent --> OrphanCheck : no
        OrphanCheck --> FlushOrphan : pending_title already set\n(two consecutive titles)\n→ flush orphan title alone
        OrphanCheck --> StorePending : no prior pending title
        FlushFirst --> StorePending
        FlushOrphan --> StorePending
        StorePending : pending_title = element.text\npending_title_label = label\npending_title_page = page_num
    }

    state ContentBranch {
        [*] --> EstTokens : estimated_tokens =\nint(len(text.split()) × 1.3)
        EstTokens --> OversizedCheck : estimated_tokens > max_chunk_tokens?
        OversizedCheck --> SplitAndEmit : yes — flush buffer\n_split_text_into_sub_chunks()\ncreate one Chunk per sub-chunk
        OversizedCheck --> OverflowCheck : no
        OverflowCheck --> FlushOverflow : current_tokens +\nestimated_tokens +\npending_tokens > max_chunk_tokens?
        FlushOverflow --> AppendContent
        OverflowCheck --> AppendContent : fits
        AppendContent : if pending_title: prepend to current_texts, clear pending_title\nif current_texts empty: current_page = page_num\ncurrent_texts.append(element.text)\ncurrent_tokens += estimated_tokens
        AppendContent --> FlushIfFull : current_tokens >= max_chunk_tokens?
        FlushIfFull --> NextElement : yes — flush()
        FlushIfFull --> NextElement : no — continue
    }

    AtomicBranch --> NextElement
    TitleBranch --> NextElement
    ContentBranch --> NextElement

    Done --> FlushRemaining : flush any remaining current_texts
    FlushRemaining --> [*] : return list[Chunk]\nchunk_id = source_file + _ + page + _ + idx
```
