"""Post-processor: converts raw parsed elements into structured Markdown."""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

logger = logging.getLogger(__name__)


@runtime_checkable
class ElementLike(Protocol):
    """Duck-typing protocol for parsed elements."""

    label: str
    text: str
    bbox: list[float]
    score: float
    reading_order: int


# Labels to skip entirely (no text output)
SKIP_LABELS: frozenset[str] = frozenset({"image", "seal", "page_number"})

# Label → Markdown transformation map
PROMPT_MAP: dict[str, Any] = {
    "document_title": lambda t: f"# {t}",
    "paragraph_title": lambda t: f"## {t}",
    "abstract": lambda t: f"**Abstract:** {t}",
    "table": lambda t: t,
    "formula": lambda t: f"\n$$\n{t}\n$$\n",
    "inline_formula": lambda t: f"\n$$\n{t}\n$$\n",
    "code_block": lambda t: f"```\n{t}\n```",
    "footnotes": lambda t: f"\n---\n{t}",
    "algorithm": lambda t: f"```\n{t}\n```",
}


def assemble_markdown(elements: list[ElementLike]) -> str:
    """Convert a list of parsed elements into a Markdown string.

    Args:
        elements: Parsed elements, each with label, text, bbox, score, reading_order.

    Returns:
        Assembled Markdown string with elements joined by double newlines.
    """
    if not elements:
        return ""

    sorted_elements = sorted(elements, key=lambda e: e.reading_order)
    parts: list[str] = []

    for element in sorted_elements:
        if element.label in SKIP_LABELS:
            logger.debug("Skipping element with label '%s'", element.label)
            continue

        transform = PROMPT_MAP.get(element.label)
        if transform is not None:
            parts.append(transform(element.text))
        else:
            # Default: plain text passthrough (paragraph, text, references, etc.)
            parts.append(element.text)

    return "\n\n".join(parts).strip()


def save_to_json(result: Any, output_dir: Path) -> None:
    """Save parse result as Markdown and structured JSON files.

    Args:
        result: ParseResult object with source_file, pages, total_elements.
        output_dir: Directory to write output files.

    Raises:
        OSError: If the output directory cannot be created or files cannot be written.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(result.source_file).stem

    # Use the SDK's full document markdown if available (it's higher quality
    # than our per-element assembler). Fall back to joining per-page markdown.
    full_markdown = getattr(result, "full_markdown", "") or ""
    if not full_markdown:
        all_markdown_parts: list[str] = []
        for page in result.pages:
            if page.markdown:
                all_markdown_parts.append(page.markdown)
        full_markdown = "\n\n".join(all_markdown_parts)

    md_path = output_dir / f"{stem}.md"
    md_path.write_text(full_markdown, encoding="utf-8")
    logger.info("Saved Markdown to %s", md_path)

    # Serialize and save structured JSON
    pages_data = []
    for page in result.pages:
        elements_data = []
        for el in page.elements:
            elements_data.append({
                "label": el.label,
                "text": el.text,
                "bbox": el.bbox,
                "score": el.score,
                "reading_order": el.reading_order,
            })
        pages_data.append({
            "page_num": page.page_num,
            "elements": elements_data,
            "markdown": page.markdown,
        })

    json_data = {
        "source_file": result.source_file,
        "total_elements": result.total_elements,
        "pages": pages_data,
    }

    json_path = output_dir / f"{stem}.json"
    json_path.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding="utf-8")
    logger.info("Saved JSON to %s", json_path)
