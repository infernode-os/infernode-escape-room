#!/usr/bin/env python3
"""Loopback OpenAI proxy providing bounded, evidence-visible quota retry."""

import argparse
import datetime
import http.server
import json
import os
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid


MAX_RESPONSE = 32 * 1024 * 1024
HOP_HEADERS = frozenset((
    "accept-encoding", "connection", "content-length", "host", "keep-alive",
    "proxy-authenticate", "proxy-authorization", "te", "trailers",
    "transfer-encoding", "upgrade",
))


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_limited(stream):
    data = stream.read(MAX_RESPONSE + 1)
    if len(data) > MAX_RESPONSE:
        raise RuntimeError("upstream response exceeds proxy limit")
    return data


def quota_error(status, body):
    candidates = []
    if status == 429:
        candidates.append(body)
    if b"data:" in body:
        for line in body.splitlines():
            if line.startswith(b"data:"):
                candidates.append(line[5:].strip())
    for candidate in candidates:
        try:
            value = json.loads(candidate)
        except (TypeError, ValueError):
            continue
        error = value.get("error") if isinstance(value, dict) else None
        if not isinstance(error, dict):
            continue
        if error.get("type") != "usage_limit" or \
                error.get("code") != "usage_limit" or \
                error.get("reason") != "usage_limit" or \
                error.get("retryable") is not True:
            continue
        return error
    return None


class QuotaState:
    def __init__(self, state_file):
        self.state_file = state_file
        self.lock = threading.Lock()
        self.paused = {}
        self.last_pause = None
        with self.lock:
            self._write_locked()

    def _snapshot_locked(self):
        retry = [entry.get("retry_at") for entry in self.paused.values()
                 if entry.get("retry_at")]
        return {
            "state": "paused_quota" if self.paused else "ready",
            "quota": {
                "paused_turns": len(self.paused),
                "retry_at": min(retry) if retry else None,
                "last_pause": self.last_pause,
            },
        }

    def _write_locked(self):
        if not self.state_file:
            return
        tmp = self.state_file + ".tmp-%d" % os.getpid()
        os.makedirs(os.path.dirname(self.state_file), mode=0o700,
                    exist_ok=True)
        with open(tmp, "w") as stream:
            json.dump(self._snapshot_locked(), stream, sort_keys=True)
            stream.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.state_file)

    def pause(self, request_id, started_at, retry_at):
        with self.lock:
            entry = self.paused.setdefault(request_id, {
                "state": "paused_quota",
                "paused_at": started_at,
            })
            entry["retry_at"] = retry_at
            self._write_locked()

    def finish(self, request_id, state):
        with self.lock:
            entry = self.paused.pop(request_id, None)
            if entry is not None:
                self.last_pause = {
                    "state": state,
                    "paused_at": entry["paused_at"],
                    "ended_at": utcnow(),
                }
            self._write_locked()

    def snapshot(self):
        with self.lock:
            return self._snapshot_locked()


class ProxyServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, upstream, max_wait, retry_interval,
                 state_file, heartbeat_interval=60):
        super().__init__(address, handler)
        self.upstream = upstream.rstrip("/")
        self.max_wait = max_wait
        self.retry_interval = retry_interval
        self.heartbeat_interval = heartbeat_interval
        self.quota_state = QuotaState(state_file)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("quota-proxy: " + fmt % args, file=sys.stderr, flush=True)

    def upstream_request(self, method, body=None):
        headers = {
            key: value for key, value in self.headers.items()
            if key.lower() not in HOP_HEADERS
        }
        request = urllib.request.Request(
            self.server.upstream + self.path, data=body,
            headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                return response.status, dict(response.headers), read_limited(response)
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), read_limited(error)

    def send_body(self, status, headers, body):
        self.send_response(status)
        for key, value in headers.items():
            if key.lower() not in HOP_HEADERS and key.lower() != "content-encoding":
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            status, headers, body = self.upstream_request("GET")
            if self.path.rstrip("/") == "/health" and status == 200:
                health = json.loads(body)
                health.update(self.server.quota_state.snapshot())
                health["quota_recovery"] = True
                health["quota_recovery_owner"] = "infernode-escape-room"
                body = json.dumps(health, sort_keys=True).encode()
                headers["Content-Type"] = "application/json"
            self.send_body(status, headers, body)
        except Exception as error:  # noqa: BLE001
            body = json.dumps({"error": {"type": "proxy_error",
                                         "message": str(error)}}).encode()
            self.send_body(502, {"Content-Type": "application/json"}, body)

    def fetch_with_heartbeats(self, body, streaming):
        result = []
        failure = []
        done = threading.Event()

        def fetch():
            try:
                result.append(self.upstream_request("POST", body))
            except BaseException as error:  # noqa: BLE001
                failure.append(error)
            finally:
                done.set()

        threading.Thread(target=fetch, daemon=True).start()
        while not done.wait(self.server.heartbeat_interval):
            if streaming:
                self.wfile.write(b": escape-room quota proxy working\n\n")
                self.wfile.flush()
        if failure:
            raise failure[0]
        return result[0]

    def wait_retry(self, seconds, streaming):
        deadline = time.monotonic() + seconds
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return
            time.sleep(min(self.server.heartbeat_interval, left))
            if streaming:
                self.wfile.write(b": escape-room quota paused\n\n")
                self.wfile.flush()

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400, "invalid content length")
            return
        if length < 0 or length > MAX_RESPONSE:
            self.send_error(413, "request exceeds proxy limit")
            return
        body = self.rfile.read(length)
        try:
            request_json = json.loads(body)
            streaming = request_json.get("stream") is True
        except (TypeError, ValueError):
            streaming = False

        if streaming:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.flush()

        request_id = uuid.uuid4().hex
        paused_mono = None
        paused_utc = None
        try:
            while True:
                status, headers, response = self.fetch_with_heartbeats(
                    body, streaming)
                quota = quota_error(status, response)
                if quota is None:
                    if paused_mono is not None:
                        self.server.quota_state.finish(request_id, "resumed")
                    if streaming:
                        if status == 200:
                            self.wfile.write(response)
                        else:
                            payload = response if response else json.dumps({
                                "error": {"type": "upstream_error",
                                          "status": status}}).encode()
                            self.wfile.write(b"data: " + payload +
                                             b"\n\ndata: [DONE]\n\n")
                        self.wfile.flush()
                    else:
                        self.send_body(status, headers, response)
                    return

                if paused_mono is None:
                    paused_mono = time.monotonic()
                    paused_utc = utcnow()
                elapsed = time.monotonic() - paused_mono
                if elapsed >= self.server.max_wait:
                    self.server.quota_state.finish(request_id, "exhausted")
                    if streaming:
                        self.wfile.write(response)
                        self.wfile.flush()
                    else:
                        self.send_body(status, headers, response)
                    return
                delay = quota.get("retry_after")
                if not isinstance(delay, (int, float)) or delay <= 0:
                    delay = self.server.retry_interval
                # Provider reset timestamps can remain stale after their stated
                # time passes. Treat the configured retry interval as a polling
                # ceiling, not merely a fallback, so one stale response cannot
                # defer the preserved turn until the whole recovery window ends.
                delay = min(float(delay), self.server.retry_interval,
                            self.server.max_wait - elapsed)
                retry_at = (datetime.datetime.now(datetime.timezone.utc) +
                            datetime.timedelta(seconds=delay)).isoformat()
                self.server.quota_state.pause(request_id, paused_utc, retry_at)
                self.wait_retry(delay, streaming)
        except (BrokenPipeError, ConnectionResetError):
            if paused_mono is not None:
                self.server.quota_state.finish(request_id, "caller_gone")
        except Exception as error:  # noqa: BLE001
            if paused_mono is not None:
                self.server.quota_state.finish(request_id, "proxy_error")
            if not streaming:
                payload = json.dumps({"error": {"type": "proxy_error",
                                                 "message": str(error)}}).encode()
                self.send_body(502, {"Content-Type": "application/json"}, payload)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True,
                        help="upstream gateway root, without /v1")
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--max-wait", type=float, default=21600)
    parser.add_argument("--retry-interval", type=float, default=300)
    parser.add_argument("--heartbeat-interval", type=float, default=60)
    parser.add_argument("--state-file")
    args = parser.parse_args()
    if args.max_wait <= 0 or args.retry_interval <= 0 or \
            args.heartbeat_interval <= 0:
        parser.error("wait intervals must be positive")

    server = ProxyServer((args.listen, args.port), Handler, args.upstream,
                         args.max_wait, args.retry_interval, args.state_file,
                         args.heartbeat_interval)
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(
        target=server.shutdown, daemon=True).start())
    host, port = server.server_address
    print("READY http://%s:%d/v1" % (host, port), flush=True)
    server.serve_forever(poll_interval=0.5)
    server.server_close()


if __name__ == "__main__":
    main()
