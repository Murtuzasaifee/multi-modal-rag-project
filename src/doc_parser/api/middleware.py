"""Loguru request/response logging middleware."""
from __future__ import annotations

import time
import uuid

from loguru import logger
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class LoggingMiddleware(BaseHTTPMiddleware):
    """Log every HTTP request with method, path, status code, and latency."""

    async def dispatch(self, request: Request, call_next) -> Response:  # type: ignore[override]
        start = time.perf_counter()
        request_id = str(uuid.uuid4())[:8]

        with logger.contextualize(request_id=request_id):
            logger.info(f"→ {request.method} {request.url.path}")
            try:
                response: Response = await call_next(request)
            except Exception:
                ms = (time.perf_counter() - start) * 1000
                logger.exception(f"← 500 ({ms:.1f}ms) — unhandled exception")
                raise
            ms = (time.perf_counter() - start) * 1000
            logger.info(f"← {response.status_code} ({ms:.1f}ms)")

        response.headers["X-Request-Id"] = request_id
        return response
