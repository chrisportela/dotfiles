"""Capture the SAML assertion that the IdP posts back to the loopback listener.

The AWS Client VPN SAML flow ends with the identity provider redirecting the
browser to an HTTP POST at http://127.0.0.1:<port>/ whose body carries the
base64 SAML assertion in the `SAMLResponse` form field. This serves exactly
that one request, writes the decoded assertion to --output, and exits.
"""

import argparse
import os
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

MAX_BODY = 4 * 1024 * 1024

PAGE = b"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>AWS Client VPN</title>
    <style>
      body { font: 16px/1.5 system-ui, sans-serif; margin: 6rem auto; max-width: 30rem;
             color: #1c1c1c; background: #fafafa; }
      p { color: #555; }
      @media (prefers-color-scheme: dark) {
        body { color: #eee; background: #161616; }
        p { color: #aaa; }
      }
    </style>
  </head>
  <body>
    <h1>Authentication received</h1>
    <p>The VPN tunnel is starting in your terminal. You can close this tab.</p>
  </body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    assertion = None

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self.send_error(400, "unexpected body length")
            return

        body = self.rfile.read(length).decode("utf-8", "replace")
        fields = urllib.parse.parse_qs(body)
        assertion = (fields.get("SAMLResponse") or [""])[0]
        if not assertion:
            self.send_error(400, "no SAMLResponse field in the POST body")
            return

        Handler.assertion = assertion
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def do_GET(self):
        # The IdP only ever POSTs here; anything else is a stray browser request.
        self.send_error(405, "waiting for the identity provider to post back")

    def log_message(self, fmt, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=35001)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    try:
        server = HTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as err:
        sys.exit(f"cannot listen on 127.0.0.1:{args.port}: {err}")

    server.timeout = 1.0
    deadline = time.monotonic() + args.timeout
    while Handler.assertion is None and time.monotonic() < deadline:
        server.handle_request()
    server.server_close()

    if Handler.assertion is None:
        sys.exit(f"timed out after {args.timeout:.0f}s waiting for the SAML response")

    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(Handler.assertion)


if __name__ == "__main__":
    main()
