"""Launch the doc-parser FastAPI server with uvicorn."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Ensure src/ is on the path when run directly
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import uvicorn

from doc_parser.config import get_settings


def main() -> None:
    """Parse CLI args and start uvicorn."""
    settings = get_settings()

    parser = argparse.ArgumentParser(description="Start the doc-parser RAG API server.")
    parser.add_argument("--host", default=settings.api_host, help="Bind host (default: %(default)s)")
    parser.add_argument("--port", type=int, default=settings.api_port, help="Bind port (default: %(default)s)")
    parser.add_argument("--workers", type=int, default=settings.api_workers, help="Number of worker processes (default: %(default)s)")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development.")
    args = parser.parse_args()

    uvicorn.run(
        "doc_parser.api.app:app",
        host=args.host,
        port=args.port,
        workers=args.workers if not args.reload else 1,
        reload=args.reload,
        log_config=None,  # Disable uvicorn's own logging; loguru handles it
    )


if __name__ == "__main__":
    main()
