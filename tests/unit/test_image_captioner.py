"""Unit tests for image_captioner — table JSON parsing, validation, and context helpers."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from doc_parser.chunker import Chunk  # noqa: E402
from doc_parser.ingestion.image_captioner import (  # noqa: E402
    _get_surrounding_context,
    _parse_image_response,
    _parse_table_json_response,
    _validate_table_extraction,
)

# ── Helpers ──────────────────────────────────────────────────────────────────

def _make_chunk(text: str = "", modality: str = "text", page: int = 1) -> Chunk:
    return Chunk(
        text=text,
        chunk_id="test_chunk",
        page=page,
        element_types=["text"],
        bbox=None,
        source_file="test.pdf",
        is_atomic=False,
        modality=modality,
    )


# ── _parse_table_json_response ───────────────────────────────────────────────


class TestParseTableJsonResponse:
    def test_valid_json_with_all_fields(self):
        raw_ocr = "col1 col2\nval1 val2"
        json_str = json.dumps({
            "num_columns": 2,
            "num_rows": 1,
            "markdown_table": "| col1 | col2 |\n|---|---|\n| val1 | val2 |",
            "summary": "A table comparing col1 and col2 values.",
        })
        caption, text = _parse_table_json_response(raw_ocr, json_str)
        assert "col1" in caption
        assert "col2" in caption
        assert "| val1 | val2 |" in caption
        assert "comparing" in text

    def test_malformed_json_falls_back_to_raw(self):
        raw_ocr = "original table text"
        caption, text = _parse_table_json_response(raw_ocr, "not json at all")
        assert caption == raw_ocr
        assert text == raw_ocr

    def test_empty_fields_fall_back_to_raw(self):
        raw_ocr = "original table text"
        json_str = json.dumps({
            "num_columns": 0,
            "num_rows": 0,
            "markdown_table": "",
            "summary": "",
        })
        caption, text = _parse_table_json_response(raw_ocr, json_str)
        assert caption == raw_ocr
        assert text == raw_ocr

    def test_missing_markdown_uses_raw_for_caption(self):
        raw_ocr = "original table text"
        json_str = json.dumps({
            "num_columns": 2,
            "num_rows": 1,
            "summary": "A summary.",
        })
        caption, text = _parse_table_json_response(raw_ocr, json_str)
        assert caption == raw_ocr  # no markdown_table key
        assert text == "A summary."

    def test_missing_summary_uses_raw_for_text(self):
        raw_ocr = "original table text"
        json_str = json.dumps({
            "num_columns": 2,
            "num_rows": 1,
            "markdown_table": "| a | b |\n|---|---|\n| 1 | 2 |",
        })
        caption, text = _parse_table_json_response(raw_ocr, json_str)
        assert "| a | b |" in caption
        assert text == raw_ocr  # no summary key

    def test_none_json_str_falls_back(self):
        raw_ocr = "original"
        caption, text = _parse_table_json_response(raw_ocr, None)
        assert caption == raw_ocr
        assert text == raw_ocr


# ── _validate_table_extraction ───────────────────────────────────────────────


class TestValidateTableExtraction:
    def test_matching_counts_passes(self):
        md = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |"
        assert _validate_table_extraction("raw", 3, 2, md) is True

    def test_missing_rows_fails(self):
        md = "| A | B |\n|---|---|\n| 1 | 2 |"
        assert _validate_table_extraction("raw", 5, 2, md) is False

    def test_empty_markdown_passes(self):
        assert _validate_table_extraction("raw", 5, 2, "") is True

    def test_zero_reported_rows_passes(self):
        assert _validate_table_extraction("raw", 0, 2, "| A |\n|---|\n| 1 |") is True

    def test_extra_rows_within_tolerance(self):
        md = "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |"
        assert _validate_table_extraction("raw", 3, 1, md) is True

    def test_significantly_extra_rows_fails(self):
        # 10 data rows reported but only 2 in markdown
        md = "| A |\n|---|\n| 1 |\n| 2 |"
        assert _validate_table_extraction("raw", 10, 1, md) is False


# ── _parse_image_response ────────────────────────────────────────────────────


class TestParseImageResponse:
    def test_extracts_caption_line(self):
        text = (
            "TYPE: DIAGRAM\n"
            "CAPTION: A flowchart showing the data pipeline.\n"
            "DETAIL:\n- Step 1\n"
            "STRUCTURE:\n- Module A\n"
        )
        caption, full = _parse_image_response(text)
        assert caption == "A flowchart showing the data pipeline."
        assert "TYPE: DIAGRAM" in full

    def test_fallback_when_no_caption_line(self):
        text = "Just some raw description of the figure without labels."
        caption, full = _parse_image_response(text)
        assert caption == text[:200]
        assert full == text

    def test_empty_text(self):
        caption, full = _parse_image_response("")
        assert caption == ""
        assert full == ""


# ── _get_surrounding_context ─────────────────────────────────────────────────


class TestGetSurroundingContext:
    def test_extracts_adjacent_text_chunks(self):
        chunks = [
            _make_chunk("Before text.", modality="text", page=1),
            _make_chunk("", modality="image", page=1),
            _make_chunk("After text.", modality="text", page=1),
        ]
        ctx = _get_surrounding_context(chunks, 1)
        assert "Before text." in ctx
        assert "After text." in ctx

    def test_skips_non_text_chunks(self):
        chunks = [
            _make_chunk("", modality="table", page=1),
            _make_chunk("", modality="image", page=1),
            _make_chunk("", modality="formula", page=1),
        ]
        ctx = _get_surrounding_context(chunks, 1)
        assert ctx == ""

    def test_skips_distant_pages(self):
        chunks = [
            _make_chunk("Far away page.", modality="text", page=1),
            _make_chunk("", modality="image", page=5),
            _make_chunk("Also far.", modality="text", page=10),
        ]
        ctx = _get_surrounding_context(chunks, 1)
        assert ctx == ""

    def test_handles_first_chunk(self):
        chunks = [
            _make_chunk("", modality="image", page=1),
            _make_chunk("After.", modality="text", page=1),
        ]
        ctx = _get_surrounding_context(chunks, 0)
        assert "After." in ctx

    def test_handles_last_chunk(self):
        chunks = [
            _make_chunk("Before.", modality="text", page=1),
            _make_chunk("", modality="image", page=1),
        ]
        ctx = _get_surrounding_context(chunks, 1)
        assert "Before." in ctx

    def test_truncates_long_context(self):
        chunks = [
            _make_chunk("A" * 500, modality="text", page=1),
            _make_chunk("", modality="image", page=1),
            _make_chunk("B" * 500, modality="text", page=1),
        ]
        ctx = _get_surrounding_context(chunks, 1, max_chars=100)
        assert len(ctx) <= 200  # max_chars * 2
