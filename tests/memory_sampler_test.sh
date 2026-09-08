#!/bin/sh
# Model-free runtime check for trusted campaign memory telemetry.

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EMU=$INFERNODE_ROOT/emu/Linux/o.emu
[ -x "$EMU" ] || { echo "memory_sampler_test: SKIP (Linux emulator not built)"; exit 0; }

name=memory-sampler-test-$$
relative=tmp/infernode-escape-room/$name
staged=$INFERNODE_ROOT/$relative
log=$INFERNODE_ROOT/$relative.log
stop=$INFERNODE_ROOT/$relative.stop
mkdir -p "$(dirname "$staged")"
cp "$ROOT/guest/memory-sampler" "$staged"
chmod 0700 "$staged"
trap 'rm -f "$staged" "$log" "$stop"' EXIT HUP INT TERM

EMU="$EMU" INFERNODE_ROOT="$INFERNODE_ROOT" SCRIPT="/$relative" \
	LOG="$log" STOP="$stop" python3 - <<'PY'
import os
import signal
import subprocess
import time

process = subprocess.Popen([
    os.environ["EMU"], "-c1", "-pheap=128m", "-pmain=128m", "-pimage=128m",
    "-r" + os.environ["INFERNODE_ROOT"], "sh", "-c",
    "run %s %s.log %s.pause %s.stop" % (
        os.environ["SCRIPT"], os.environ["SCRIPT"], os.environ["SCRIPT"],
        os.environ["SCRIPT"]),
], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True)

log = os.environ["LOG"]
stop = os.environ["STOP"]
try:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if os.path.exists(log) and "@@MEMORY end" in open(log).read():
            break
        if process.poll() is not None:
            raise SystemExit("emulator exited before memory sample")
        time.sleep(0.1)
    else:
        raise SystemExit("memory sample timed out")

    open(stop, "w").close()
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if "@@MEMORY sampler-stopped" in open(log).read():
            break
        time.sleep(0.1)
    else:
        raise SystemExit("memory sampler did not stop promptly")
finally:
    if process.poll() is None:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            process.wait(timeout=5)
PY

grep -q ' main$' "$log"
grep -q '^@@MEMORY sampler-stopped$' "$log"
echo "memory_sampler_test: PASS"
