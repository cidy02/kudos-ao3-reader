#!/usr/bin/env python3
"""Local-only request logger for the Kudos security audit. Binds 127.0.0.1."""
from __future__ import annotations

import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18765
LOG = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/kudos-audit-beacon.log")
TINY_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00"
    b"\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
)


class Handler(BaseHTTPRequestHandler):
    def _record(self) -> None:
        ua = self.headers.get("User-Agent", "")
        cookie = self.headers.get("Cookie", "")
        origin = self.headers.get("Origin", "")
        referer = self.headers.get("Referer", "")
        line = (
            f"{self.command} {self.path} ua={ua!r} cookie={cookie!r} "
            f"origin={origin!r} referer={referer!r}\n"
        )
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as handle:
            handle.write(line)

    def do_GET(self) -> None:  # noqa: N802
        self._record()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(TINY_PNG)

    def do_POST(self) -> None:  # noqa: N802
        self._record()
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._record()
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def log_message(self, fmt: str, *args) -> None:
        return


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
