"""Chandra OCR parser backend using the chandra-ocr library with vLLM."""
from __future__ import annotations

import logging
from pathlib import Path

from tqdm import tqdm

from doc_parser.config import get_settings
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
    """Document parser using Chandra OCR via a local vLLM server.

    Requires vLLM >= 0.17.0 (first version supporting Qwen3_5ForConditionalGeneration).

    Start the server before use:
        vllm serve datalab-to/chandra-ocr-2 --served-model-name chandra --port 8001

    Install:
        uv pip install vllm                # server
        uv pip install -e ".[chandra]"     # chandra-ocr client library

    Example:
        parser = ChandraParser()
        result = parser.parse_file(Path("document.pdf"))
        result.save(Path("./output"))
    """

    def __init__(self) -> None:
        try:
            from chandra.input import load_file
            from chandra.model import InferenceManager
            from chandra.model.schema import BatchInputItem
        except ImportError:
            raise ImportError(
                "chandra-ocr package is required. "
                "Install with: uv pip install -e '.[chandra]'"
            )

        settings = get_settings()
        self._load_file = load_file
        self._BatchInputItem = BatchInputItem
        self._manager = InferenceManager(method="vllm")
        self._vllm_api_base = f"http://{settings.chandra_host}:{settings.chandra_port}/v1"
        logger.info("ChandraParser initialized, endpoint: %s", self._vllm_api_base)

    def parse_file(self, file_path: str | Path) -> ParseResult:
        """Parse a single PDF or image file.

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

        batch = [
            self._BatchInputItem(image=img, prompt_type="ocr_layout")
            for img in page_images
        ]

        logger.debug(
            "ChandraParser: sending %d pages to vLLM at %s", total_pages, self._vllm_api_base
        )
        outputs = self._manager.generate(batch=batch, vllm_api_base=self._vllm_api_base)

        pages = [_output_to_page(output, idx + 1) for idx, output in enumerate(outputs)]
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
