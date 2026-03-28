"""End-to-end integration test for the document parsing pipeline.

These tests require a valid Z_AI_API_KEY environment variable and make real
network calls to the Z.AI MaaS API. Skip automatically when the key is absent.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

# Add src/ to Python path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

# Skip entire module if Z_AI_API_KEY is not set
pytestmark = pytest.mark.skipif(
    not os.getenv("Z_AI_API_KEY"),
    reason="Z_AI_API_KEY not set — skipping integration tests",
)


@pytest.fixture(scope="module")
def sample_image(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Create a simple sample document image for testing."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        pytest.skip("Pillow not installed")

    img = Image.new("RGB", (800, 1100), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Draw some simple text to simulate a document page
    draw.text((50, 50), "Sample Document Title", fill=(0, 0, 0))
    draw.text(
        (50, 120), "Abstract: This is a test document for integration testing.", fill=(0, 0, 0)
    )
    draw.text((50, 200), "1. Introduction", fill=(0, 0, 0))
    draw.text((50, 250), "This section introduces the topic.", fill=(0, 0, 0))

    fixtures_dir = Path(__file__).parent / "fixtures"
    fixtures_dir.mkdir(parents=True, exist_ok=True)
    img_path = fixtures_dir / "sample_page.png"
    img.save(str(img_path))
    return img_path


@pytest.mark.integration
class TestPipelineE2E:
    """End-to-end tests requiring a live Z.AI API connection."""

    def test_parse_file_returns_parse_result(self, sample_image: Path) -> None:
        """DocumentParser.parse_file() returns a non-empty ParseResult."""
        from doc_parser.pipeline import DocumentParser, ParseResult

        parser = DocumentParser()
        result = parser.parse_file(sample_image)

        assert isinstance(result, ParseResult)
        assert result.source_file == str(sample_image)

    def test_parse_result_has_pages(self, sample_image: Path) -> None:
        """ParseResult contains at least one page."""
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)

        assert len(result.pages) >= 1

    def test_parse_result_has_elements(self, sample_image: Path) -> None:
        """ParseResult contains at least one element."""
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)

        assert result.total_elements >= 1

    def test_markdown_output_is_non_empty(self, sample_image: Path) -> None:
        """Assembled Markdown for the document is a non-empty string."""
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)

        all_markdown = "\n\n".join(p.markdown for p in result.pages if p.markdown)
        assert isinstance(all_markdown, str)
        assert len(all_markdown.strip()) > 0

    def test_chunks_are_generated(self, sample_image: Path) -> None:
        """structure_aware_chunking produces at least one chunk from parsed result."""
        from doc_parser.chunker import structure_aware_chunking
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)

        all_chunks = []
        for page in result.pages:
            chunks = structure_aware_chunking(
                page.elements,
                source_file=sample_image.name,
                page=page.page_num,
            )
            all_chunks.extend(chunks)

        assert len(all_chunks) >= 1

    def test_save_creates_output_files(self, sample_image: Path, tmp_path: Path) -> None:
        """ParseResult.save() creates .md and .json files in the output directory."""
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)
        result.save(tmp_path)

        stem = sample_image.stem
        assert (tmp_path / f"{stem}.md").exists()
        assert (tmp_path / f"{stem}.json").exists()

    def test_json_output_is_valid(self, sample_image: Path, tmp_path: Path) -> None:
        """Saved JSON output is valid and contains expected top-level keys."""
        from doc_parser.pipeline import DocumentParser

        parser = DocumentParser()
        result = parser.parse_file(sample_image)
        result.save(tmp_path)

        stem = sample_image.stem
        json_path = tmp_path / f"{stem}.json"
        data = json.loads(json_path.read_text(encoding="utf-8"))

        assert "source_file" in data
        assert "pages" in data
        assert "total_elements" in data
        assert isinstance(data["pages"], list)
