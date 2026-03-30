"""dots.mocr parser backend using rednote-hilab/dots.mocr via vLLM."""
from __future__ import annotations

import json
import logging
from pathlib import Path

from tqdm import tqdm

from doc_parser.config import get_settings
from doc_parser.pipeline import ParsedElement, PageResult, ParseResult

logger = logging.getLogger(__name__)

# Map dots.mocr element categories to downstream labels
_LABEL_MAP: dict[str, str] = {
    "Title": "document_title",
    "Section-header": "paragraph_title",
    "Text": "paragraph",
    "Table": "table",
    "Formula": "formula",
    "Caption": "paragraph_title",
    "Picture": "image",
    "Figure": "image",
    "List-item": "paragraph",
    "Footnote": "footnotes",
    "Complex-Block": "paragraph",
}

# Labels to drop entirely
_SKIP_LABELS: frozenset[str] = frozenset({"Page-footer", "Page-header"})

_PROMPT_MODE = "prompt_layout_all_en"


def _parse_output(raw: str, image_size: tuple[int, int]) -> tuple[list[ParsedElement], str]:
    """Parse raw model output (JSON) into elements and a markdown string."""
    elements: list[ParsedElement] = []
    text_lines: list[str] = []
    width, height = image_size

    try:
        data = json.loads(raw)
        items: list[dict] = data if isinstance(data, list) else data.get("elements", [])
        for item in items:
            category = item.get("category", "Text")
            if category in _SKIP_LABELS:
                continue
            label = _LABEL_MAP.get(category, "paragraph")
            text = item.get("text", item.get("content", ""))
            raw_bbox = item.get("bbox", [0, 0, width, height])
            bbox = [
                raw_bbox[0] / width,
                raw_bbox[1] / height,
                raw_bbox[2] / width,
                raw_bbox[3] / height,
            ]
            elements.append(
                ParsedElement(
                    label=label,
                    text=text,
                    bbox=bbox,
                    score=1.0,
                    reading_order=len(elements),
                )
            )
            if text:
                text_lines.append(text)
    except (json.JSONDecodeError, KeyError, TypeError):
        # Fallback: treat entire output as a single paragraph
        if raw.strip():
            elements.append(
                ParsedElement(
                    label="paragraph",
                    text=raw.strip(),
                    bbox=[0.0, 0.0, 1.0, 1.0],
                    score=1.0,
                    reading_order=0,
                )
            )
            text_lines.append(raw.strip())

    return elements, "\n\n".join(text_lines)


class MocrParser:
    """Document parser using dots.mocr via a local vLLM server.

    Requires vLLM >= 0.11.0.

    Start the server before use:
        vllm serve rednote-hilab/dots.mocr \\
            --served-model-name model \\
            --trust-remote-code \\
            --chat-template-content-format string \\
            --port 8002

    Install:
        uv pip install -e ".[mocr]"   # installs vllm + dots_mocr (transformer conflict resolved via uv override)

    Example:
        parser = MocrParser()
        result = parser.parse_file(Path("document.pdf"))
        result.save(Path("./output"))
    """

    def __init__(self) -> None:
        try:
            from dots_mocr.model.inference import inference_with_vllm
            from dots_mocr.utils import dict_promptmode_to_prompt
        except ImportError:
            raise ImportError(
                "dots_mocr package is required. "
                "Install with: uv pip install -e '.[mocr]'"
            )

        import fitz  # PyMuPDF — already a project dependency

        settings = get_settings()
        self._inference = inference_with_vllm
        self._prompt = dict_promptmode_to_prompt[_PROMPT_MODE]
        self._api_base = f"http://{settings.mocr_host}:{settings.mocr_port}/v1"
        self._fitz = fitz
        logger.info("MocrParser initialized, endpoint: %s", self._api_base)

    def _to_pil_images(self, file_path: Path):
        """Convert a PDF or image file to a list of PIL Images."""
        from PIL import Image

        if file_path.suffix.lower() == ".pdf":
            doc = self._fitz.open(str(file_path))
            mat = self._fitz.Matrix(200 / 72, 200 / 72)  # 200 DPI
            images = []
            for page in doc:
                pix = page.get_pixmap(matrix=mat)
                images.append(Image.frombytes("RGB", [pix.width, pix.height], pix.samples))
            return images
        else:
            return [Image.open(file_path).convert("RGB")]

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

        logger.info("MocrParser: parsing file: %s", file_path)

        images = self._to_pil_images(file_path)
        total_pages = len(images)
        logger.info("MocrParser: %d pages loaded from %s", total_pages, file_path.name)

        logger.debug("MocrParser: sending %d pages to vLLM at %s", total_pages, self._api_base)
        outputs = self._inference(
            images=images,
            prompt_mode=_PROMPT_MODE,
            api_base=self._api_base,
            model_name="model",
        )

        pages: list[PageResult] = []
        for idx, (raw, img) in enumerate(zip(outputs, images)):
            elements, markdown = _parse_output(raw, img.size)
            pages.append(PageResult(page_num=idx + 1, elements=elements, markdown=markdown))

        total_elements = sum(len(p.elements) for p in pages)
        full_markdown = "\n\n".join(p.markdown for p in pages if p.markdown)

        logger.info(
            "MocrParser: parsed %s: %d pages, %d elements",
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
                logger.error("MocrParser: failed to parse %s: %s", fp, e, exc_info=True)
                raise
        return results
