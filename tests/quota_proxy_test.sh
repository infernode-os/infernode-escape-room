#!/bin/sh
set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}

python3 - "$ROOT" <<'PY'
import importlib.util
import io
import json
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "quota_proxy", root / "scripts/quota-proxy.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)

calls = {}
bodies = {}
call_times = {}

class Upstream(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            value = {"status": "ok", "backend": "mock", "stateless": True,
                     "hardened": True, "disabled_features": ["plugins"]}
        else:
            value = {"object": "list", "data": [{"id": "default"}]}
        self.reply(200, json.dumps(value).encode())

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        calls[self.path] = calls.get(self.path, 0) + 1
        bodies.setdefault(self.path, []).append(body)
        call_times.setdefault(self.path, []).append(time.monotonic())
        usage = {"error": {"message": "limited", "type": "usage_limit",
                           "code": "usage_limit", "reason": "usage_limit",
                           "retryable": True, "retry_after": 3600}}
        capacity = {"error": {"message": "busy", "type": "model_capacity",
                              "code": "model_capacity", "reason": "model_capacity",
                              "retryable": True, "retry_after": 0.02}}
        if self.path == "/v1/stream" and calls[self.path] == 1:
            payload = b"data: " + json.dumps(usage).encode() + b"\n\ndata: [DONE]\n\n"
            self.reply(200, payload, "text/event-stream")
        elif self.path == "/v1/plain" and calls[self.path] == 1:
            self.reply(429, json.dumps(usage).encode())
        elif self.path == "/v1/capacity" and calls[self.path] == 1:
            self.reply(503, json.dumps(capacity).encode())
        elif self.path == "/v1/untrusted-capacity":
            fake = {"error": {
                "message": "Selected model is at capacity",
                "type": "gate_error", "code": "gate_error",
                "reason": "model_capacity", "retryable": True}}
            self.reply(503, json.dumps(fake).encode())
        elif self.path == "/v1/untrusted":
            payload = b'data: {"choices":[{"delta":{"content":"usage limit"}}]}\n\ndata: [DONE]\n\n'
            self.reply(200, payload, "text/event-stream")
        else:
            payload = b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n'
            self.reply(200, payload, "text/event-stream")

upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
threading.Thread(target=upstream.serve_forever, daemon=True).start()

with tempfile.TemporaryDirectory() as td:
    state = str(Path(td) / "quota-state.json")
    server = proxy.ProxyServer(
        ("127.0.0.1", 0), proxy.Handler,
        "http://127.0.0.1:%d" % upstream.server_address[1],
        2, 0.02, state, 0.01)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % server.server_address[1]
    body = b'{"model":"default","messages":[{"role":"user","content":"exact"}],"stream":true}'

    for path in ("/v1/stream", "/v1/plain", "/v1/capacity"):
        request = urllib.request.Request(
            base + path, data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=5) as response:
            result = response.read()
        assert b'"content":"ok"' in result, (path, result)
        assert b'usage_limit' not in result, (path, result)
        assert bodies[path] == [body, body], (path, bodies[path])
        assert call_times[path][1] - call_times[path][0] < 0.5, call_times[path]
        if path == "/v1/stream":
            assert result.count(b": escape-room transient retry paused") <= 3, result

    request = urllib.request.Request(
        base + "/v1/untrusted", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        result = response.read()
    assert b"usage limit" in result
    assert calls["/v1/untrusted"] == 1

    request = urllib.request.Request(
        base + "/v1/untrusted-capacity", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        result = response.read()
    assert b'"type": "gate_error"' in result, result
    assert calls["/v1/untrusted-capacity"] == 1

    with urllib.request.urlopen(base + "/health", timeout=5) as response:
        health = json.load(response)
    assert health["quota_recovery"] is True
    assert health["transient_recovery"] is True
    assert health["quota_recovery_owner"] == "infernode-escape-room"
    assert health["state"] == "ready"
    assert health["quota"]["last_pause"]["state"] == "resumed"
    assert health["retry"]["last_pause"]["reason"] == "model_capacity"
    saved = json.loads(Path(state).read_text())
    assert saved["state"] == "ready"

    server.shutdown()
    server.server_close()

upstream.shutdown()
upstream.server_close()
print("quota_proxy_test: PASS")
PY
