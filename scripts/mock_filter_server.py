#!/usr/bin/env python3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE_ETAG = '"etag-a"'
NEW_ETAG = '"etag-b"'
LAST_MODIFIED = 'Sat, 14 Feb 2026 00:00:00 GMT'
FILTER_BODY = b"! Title: Example\n! Version: 1\n||ads.example^\n"
UPDATED_BODY = b"! Title: Example\n! Version: 2\n||ads.example^\n||tracker.example^\n"
HTML_BODY = b"<!doctype html><html><body>challenge</body></html>"


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body=b"", headers=None):
        self.send_response(status)
        headers = headers or {}
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, b"ok")
            return

        if self.path == "/conditional":
            if self.headers.get("If-None-Match") == BASE_ETAG:
                self._send(304)
                return
            self._send(200, FILTER_BODY, {
                "ETag": BASE_ETAG,
                "Last-Modified": LAST_MODIFIED,
                "Content-Type": "text/plain; charset=utf-8",
            })
            return

        if self.path == "/same-content-new-etag":
            self._send(200, FILTER_BODY, {
                "ETag": NEW_ETAG,
                "Last-Modified": LAST_MODIFIED,
                "Content-Type": "text/plain; charset=utf-8",
            })
            return

        if self.path == "/updated-content":
            self._send(200, UPDATED_BODY, {
                "ETag": NEW_ETAG,
                "Last-Modified": LAST_MODIFIED,
                "Content-Type": "text/plain; charset=utf-8",
            })
            return

        if self.path == "/html-challenge":
            self._send(200, HTML_BODY, {
                "Content-Type": "text/html; charset=utf-8",
            })
            return

        if self.path == "/server-error":
            self._send(500, b"error")
            return

        self._send(404, b"not found")

    def log_message(self, *_args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18765
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"mock_filter_server listening on 127.0.0.1:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
