"""Pytest configuration and shared fixtures."""
from __future__ import annotations

import pytest


def pytest_configure(config: pytest.Config) -> None:
    """Register custom markers."""
    config.addinivalue_line("markers", "integration: requires external API (Z_AI_API_KEY)")
