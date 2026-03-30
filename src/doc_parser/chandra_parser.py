"""Chandra OCR parser backend using the chandra-ocr library with HuggingFace."""
from __future__ import annotations

import logging
import os
from pathlib import Path

from tqdm import tqdm

from doc_parser.pipeline import ParsedElement, PageResult, ParseResult

logger = logging.getLogger(__name__)

# Map Chandra OCR layout labels to GLM-OCR compatible labels used downstream
_LABEL_MAP: dict[str, str] = {
    "Section-Header": "paragraph_title",
    "Text": "paragraph",
    "Table": "table",
    "Equation-Block": "formula",
    "Chemical-Block": "formula",
    "Code-Block": "code_block",
    "Caption": "paragraph_title",
    "Image": "image",
    "Figure": "image",
    "Diagram": "image",
    "List-Group": "paragraph",
    "Footnote": "footnotes",
    "Complex-Block": "paragraph",
    "Form": "paragraph",
    "Table-Of-Contents": "paragraph",
    "Bibliography": "paragraph",
}

# Labels to drop entirely (headers/footers/blank pages add noise)
_SKIP_LABELS: frozenset[str] = frozenset({"Page-Header", "Page-Footer", "Blank-Page"})


def _output_to_page(output, page_num: int) -> PageResult:
    """Convert a single BatchOutputItem to a PageResult."""
    elements: list[ParsedElement] = []
    for chunk in output.chunks or []:
        chandra_label = chunk.get("label", "Text")
        if chandra_label in _SKIP_LABELS:
            continue
        label = _LABEL_MAP.get(chandra_label, "paragraph")
        # bbox_scale defaults to 1000 — normalise to [0, 1]
        raw_bbox = chunk.get("bbox", [0, 0, 1000, 1000])
        bbox = [v / 1000.0 for v in raw_bbox]
        elements.append(
            ParsedElement(
                label=label,
                text=chunk.get("content", ""),
                bbox=bbox,
                score=1.0,
                reading_order=len(elements),
            )
        )
    return PageResult(page_num=page_num, elements=elements, markdown=output.markdown or "")


class ChandraParser:
    """Document parser using Chandra OCR via HuggingFace local inference.

    Processes each page individually (batch_size=1) to keep peak VRAM bounded.
    Uses CUDA with flash_attention_2 for optimal throughput on GPU.

    Install: uv pip install -e ".[chandra]"

    Example:
        parser = ChandraParser()
        result = parser.parse_file(Path("document.pdf"))
        result.save(Path("./output"))
    """

    def __init__(self) -> None:
        # Set before importing chandra — its Settings singleton reads os.environ
        # at import time. TORCH_DEVICE avoids device_map="auto" disk-offloading;
        # flash_attention_2 halves attention memory and improves throughput on
        # Ampere+ GPUs (L4, A10, A100, H100).
        os.environ["TORCH_DEVICE"] = "cuda"
        os.environ["TORCH_ATTN"] = "flash_attention_2"

        try:
            from chandra.input import load_file
            from chandra.model import InferenceManager
            from chandra.model.schema import BatchInputItem
        except ImportError:
            raise ImportError(
                "chandra-ocr[hf] package is required. "
                "Install with: uv pip install -e '.[chandra]'"
            )

        self._load_file = load_file
        self._BatchInputItem = BatchInputItem
        self._manager = InferenceManager(method="hf")
        logger.info("ChandraParser initialized (cuda, flash_attention_2)")

    def parse_file(self, file_path: str | Path) -> ParseResult:
        """Parse a single PDF or image file.

        Pages are processed one at a time to bound peak VRAM — no cross-page
        padding or simultaneous activation memory.

        Args:
            file_path: Path to the document to parse (PDF or image).

        Returns:
            ParseResult with structured elements and assembled Markdown.
        """
        file_path = Path(file_path)
        if not file_path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        logger.info("ChandraParser: parsing file: %s", file_path)

        page_images = self._load_file(str(file_path), {})
        total_pages = len(page_images)
        logger.info("ChandraParser: %d pages loaded from %s", total_pages, file_path.name)

        pages: list[PageResult] = []
        for page_idx, img in enumerate(page_images):
            page_num = page_idx + 1
            logger.debug("ChandraParser: processing page %d/%d", page_num, total_pages)

            # One page at a time — eliminates padding across pages and keeps
            # peak activation memory to a single page's footprint
            item = self._BatchInputItem(image=img, prompt_type="ocr_layout")
            output = self._manager.generate(batch=[item])[0]
            pages.append(_output_to_page(output, page_num))

        total_elements = sum(len(p.elements) for p in pages)
        full_markdown = "\n\n".join(p.markdown for p in pages if p.markdown)

        logger.info(
            "ChandraParser: parsed %s: %d pages, %d elements",
            file_path.name, len(pages), total_elements,
        )
        return ParseResult(
            source_file=str(file_path),
            pages=pages,
            total_elements=total_elements,
            full_markdown=full_markdown,
        )

    def parse_batch(self, file_paths: list[Path], output_dir: Path) -> list[ParseResult]:
        """Parse multiple files with progress tracking."""
        output_dir.mkdir(parents=True, exist_ok=True)
        results: list[ParseResult] = []
        for fp in tqdm(file_paths, desc="Parsing documents", unit="file"):
            try:
                result = self.parse_file(fp)
                result.save(output_dir)
                results.append(result)
            except Exception as e:
                logger.error("ChandraParser: failed to parse %s: %s", fp, e, exc_info=True)
                raise
        return results
