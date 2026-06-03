#!/usr/bin/env python3
"""
Tiny local proxy so the Ideogrammar editor (a browser page) can drive ComfyUI
without ComfyUI needing --enable-cors-header.

Why this exists:
  CORS is a *browser* rule. Your Python ComfyUIClient never hits it because it
  talks server-to-server. This proxy does the same thing: the browser talks to
  THIS server (same origin => no CORS), and this server forwards everything to
  ComfyUI exactly like a Python client would.

What it does:
  - Serves index.html at  http://<listen>/  (so the page is same-origin).
  - Transparently forwards every other HTTP request to ComfyUI
    (/prompt, /history, /view, /upload/image, /interrupt, /queue, ...).
  - Relays the /ws WebSocket to ComfyUI (raw byte relay -> live progress works).
  - Adds permissive CORS headers too, so it also works if you open the page as
    a file:// and just point its Server URL at this proxy.

Usage:
  python comfy_proxy.py
  python comfy_proxy.py --comfy http://192.168.2.33:8188 --port 8189
  # then open http://localhost:8189/ and set the editor's Server URL to
  #   http://localhost:8189   (or leave blank when served from here)

Stdlib only. Python 3.8+.
"""

import argparse
import base64
import hashlib
import http.client
import os
import select
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
}

ARGS = None  # set in main()


def comfy_host_port():
    u = urlsplit(ARGS.comfy)
    return u.hostname, (u.port or (443 if u.scheme == "https" else 80))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "ComfyProxy/1.0"

    # ---- logging: quiet but keep errors ----
    def log_message(self, fmt, *a):
        if ARGS.verbose:
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % a))

    # ---- helpers ----
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def _serve_index(self):
        try:
            with open(ARGS.html, "rb") as f:
                body = f.read()
        except OSError as e:
            self.send_error(500, "Cannot read %s: %s" % (ARGS.html, e))
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _is_ws(self):
        up = self.headers.get("Upgrade", "")
        return up.lower() == "websocket"

    # ---- HTTP verbs ----
    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if self._is_ws():
            self._relay_websocket()
            return
        if path in ("/", "/index.html"):
            self._serve_index()
            return
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    # ---- transparent HTTP proxy to ComfyUI ----
    def _proxy(self):
        host, port = comfy_host_port()
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None

        fwd = {}
        for k, v in self.headers.items():
            if k.lower() in HOP_BY_HOP or k.lower() == "host":
                continue
            fwd[k] = v
        fwd["Host"] = "%s:%s" % (host, port)

        try:
            conn = http.client.HTTPConnection(host, port, timeout=ARGS.timeout)
            conn.request(self.command, self.path, body=body, headers=fwd)
            resp = conn.getresponse()
            data = resp.read()
        except Exception as e:
            self.send_error(502, "Upstream error: %s" % e)
            return

        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() in HOP_BY_HOP or k.lower() in ("content-length", "access-control-allow-origin"):
                continue
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        conn.close()

    # ---- WebSocket relay (raw byte bridge after two independent handshakes) ----
    def _relay_websocket(self):
        # 1) Complete the handshake with the browser.
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400, "Missing Sec-WebSocket-Key")
            return
        accept = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode()).digest()
        ).decode()
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        proto = self.headers.get("Sec-WebSocket-Protocol")
        if proto:
            self.send_header("Sec-WebSocket-Protocol", proto.split(",")[0].strip())
        self.end_headers()
        self.wfile.flush()
        browser = self.connection

        # 2) Open a WebSocket to ComfyUI ourselves (act as a client).
        host, port = comfy_host_port()
        try:
            upstream = socket.create_connection((host, port), timeout=ARGS.timeout)
        except OSError as e:
            try:
                browser.close()
            except OSError:
                pass
            self.log_message("ws upstream connect failed: %s", e)
            return
        cli_key = base64.b64encode(os.urandom(16)).decode()
        req = (
            "GET %s HTTP/1.1\r\n"
            "Host: %s:%s\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        ) % (self.path, host, port, cli_key)
        try:
            upstream.sendall(req.encode())
            # read until end of upstream response headers
            buf = b""
            while b"\r\n\r\n" not in buf:
                chunk = upstream.recv(4096)
                if not chunk:
                    break
                buf += chunk
            head, _, leftover = buf.partition(b"\r\n\r\n")
            if b"101" not in head.split(b"\r\n", 1)[0]:
                self.log_message("ws upstream did not upgrade: %r", head[:80])
                upstream.close()
                browser.close()
                return
            if leftover:
                browser.sendall(leftover)  # any frames ComfyUI already sent
        except OSError as e:
            self.log_message("ws upstream handshake failed: %s", e)
            try:
                upstream.close()
                browser.close()
            except OSError:
                pass
            return

        # 3) Raw bidirectional relay. We never parse frames: ws frames are just
        #    bytes, and each side already did a valid handshake, so forwarding
        #    bytes verbatim (browser frames stay masked, server frames unmasked)
        #    is correct.
        self.close_connection = True
        socks = [browser, upstream]
        try:
            while True:
                r, _, _ = select.select(socks, [], [], 60)
                if not r:
                    continue
                for s in r:
                    try:
                        data = s.recv(65536)
                    except OSError:
                        return
                    if not data:
                        return
                    dst = upstream if s is browser else browser
                    try:
                        dst.sendall(data)
                    except OSError:
                        return
        finally:
            for s in socks:
                try:
                    s.close()
                except OSError:
                    pass


def main():
    global ARGS
    here = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description="Local same-origin proxy for the Ideogrammar editor -> ComfyUI")
    p.add_argument("--comfy", default="http://192.168.2.33:8188", help="ComfyUI base URL")
    p.add_argument("--host", default="127.0.0.1", help="address to bind (use 0.0.0.0 to expose on LAN)")
    p.add_argument("--port", type=int, default=8189, help="port to serve on")
    p.add_argument("--html", default=os.path.join(here, "index.html"), help="path to index.html")
    p.add_argument("--timeout", type=float, default=600.0, help="upstream timeout (s)")
    p.add_argument("--verbose", action="store_true", help="log every request")
    ARGS = p.parse_args()

    srv = ThreadingHTTPServer((ARGS.host, ARGS.port), Handler)
    srv.daemon_threads = True
    url = "http://%s:%s/" % ("localhost" if ARGS.host in ("127.0.0.1", "0.0.0.0") else ARGS.host, ARGS.port)
    print("Ideogrammar proxy running")
    print("  open:       %s" % url)
    print("  forwarding: %s" % ARGS.comfy)
    print("  editor Server URL: leave blank (uses this origin) or set %s" % url.rstrip("/"))
    print("Press Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped.")


if __name__ == "__main__":
    main()
