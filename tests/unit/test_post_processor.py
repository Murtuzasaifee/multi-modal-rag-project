"""Unit tests for post_processor.assemble_markdown()."""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))


# Define a local ParsedElement for testing (mirrors the real one)
@dataclass
class ParsedElement:
    label: str
    text: str
    bbox: list[float]
    score: float
    reading_order: int


# Test cases — one per label type in the PROMPT_MAP
class TestAssembleMarkdown:
    def test_document_title_becomes_h1(self):
        """document_title label maps to # heading."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("document_title", "My Paper", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "# My Paper" in result

    def test_paragraph_title_becomes_h2(self):
        """paragraph_title label maps to ## heading."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("paragraph_title", "Introduction", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "## Introduction" in result

    def test_abstract_becomes_bold_prefix(self):
        """abstract label gets bold Abstract: prefix."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("abstract", "This paper studies...", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "**Abstract:**" in result
        assert "This paper studies..." in result

    def test_formula_becomes_latex_block(self):
        """formula label wraps text in $$ delimiters."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("formula", "E = mc^2", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "$$" in result
        assert "E = mc^2" in result

    def test_inline_formula_becomes_latex_block(self):
        """inline_formula also wraps in $$ delimiters."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("inline_formula", "x^2", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "$$" in result

    def test_code_block_becomes_fenced_code(self):
        """code_block wraps in triple backticks."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("code_block", "def foo(): pass", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "```" in result
        assert "def foo(): pass" in result

    def test_table_passthrough(self):
        """table text passes through unchanged (already HTML/Markdown from GLM-OCR)."""
        from doc_parser.post_processor import assemble_markdown
        table_html = "<table><tr><td>A</td></tr></table>"
        elements = [ParsedElement("table", table_html, [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert table_html in result

    def test_footnotes_get_hr_prefix(self):
        """footnotes get a horizontal rule prefix."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("footnotes", "1. See reference", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "---" in result
        assert "1. See reference" in result

    def test_algorithm_becomes_fenced_code(self):
        """algorithm wraps in triple backticks."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("algorithm", "for i in range(n):", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "```" in result

    def test_image_is_skipped(self):
        """image elements are excluded from output."""
        from doc_parser.post_processor import assemble_markdown
        elements = [
            ParsedElement("paragraph", "Some text", [0,0,1,1], 0.9, 0),
            ParsedElement("image", "fig1.png", [0,0,1,1], 0.9, 1),
        ]
        result = assemble_markdown(elements)
        assert "fig1.png" not in result
        assert "Some text" in result

    def test_page_number_is_skipped(self):
        """page_number elements are excluded from output."""
        from doc_parser.post_processor import assemble_markdown
        elements = [
            ParsedElement("paragraph", "Content", [0,0,1,1], 0.9, 0),
            ParsedElement("page_number", "42", [0,0,1,1], 0.9, 1),
        ]
        result = assemble_markdown(elements)
        assert "42" not in result

    def test_seal_is_skipped(self):
        """seal elements are excluded from output."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("seal", "CONFIDENTIAL", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "CONFIDENTIAL" not in result

    def test_reading_order_preserved(self):
        """Elements appear in reading_order order, not insertion order."""
        from doc_parser.post_processor import assemble_markdown
        elements = [
            ParsedElement("paragraph", "Second", [0,0,1,1], 0.9, 1),
            ParsedElement("document_title", "First", [0,0,1,1], 0.9, 0),
        ]
        result = assemble_markdown(elements)
        first_pos = result.find("First")
        second_pos = result.find("Second")
        assert first_pos < second_pos

    def test_paragraph_plain_text(self):
        """paragraph and text labels output plain text."""
        from doc_parser.post_processor import assemble_markdown
        elements = [ParsedElement("paragraph", "Hello world", [0,0,1,1], 0.9, 0)]
        result = assemble_markdown(elements)
        assert "Hello world" in result

    def test_empty_elements_returns_empty(self):
        """Empty element list returns empty string."""
        from doc_parser.post_processor import assemble_markdown
        result = assemble_markdown([])
        assert result.strip() == ""
