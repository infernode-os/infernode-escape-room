#!/bin/sh
set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat > "$work/memory.log" <<'EOF'
@@MEMORY sample state=running
       1000       10000        2000          10           4           1        8000 main
       2000       20000        3000          20           8           1       15000 heap
        300        5000         400           4           2           1        4000 image
@@MEMORY end
@@MEMORY sample state=quota-paused
       1600       10000        2200          18           7           1        7000 main
       1800       20000        3000          25          14           1       15000 heap
        300        5000         400           6           4           1        4000 image
@@MEMORY end
EOF

python3 "$ROOT/scripts/analyze-memory-pools.py" "$work/memory.log" > "$work/summary.json"
python3 - "$work/summary.json" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1]))
assert value["samples"] == 2, value
assert value["last_meta"]["state"] == "quota-paused", value
assert value["pools"]["main"]["delta"] == 600, value
assert value["pools"]["main"]["active_allocations_delta"] == 5, value
assert value["pools"]["heap"]["delta"] == -200, value
PY

if python3 "$ROOT/scripts/analyze-memory-pools.py" \
	--max-main-growth 500 "$work/memory.log" >/dev/null; then
	echo "FAIL: growth threshold was not enforced" >&2
	exit 1
fi

test -x "$ROOT/guest/memory-sampler"
test -x "$ROOT/scripts/run-sse-pause-soak.sh"

# A PASS marker is the probe completion boundary. The helper must then reap the
# emulator it launched instead of waiting forever for unrelated guest services.
fake=$work/infernode
mkdir -p "$fake/emu/Linux" "$fake/tools"
: > "$fake/mkconfig"
cat > "$fake/tools/compile-limbo.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$fake/emu/Linux/o.emu" <<'EOF'
#!/bin/sh
trap 'exit 0' TERM
cat <<'DATA'
@@MEMORY sample label=start events=0
        100       10000         200          10           4           1        8000 main
@@MEMORY end
@@MEMORY sample label=finish events=1
        120       10000         220          12           5           1        8000 main
@@MEMORY end
@@SOAK PASS events=1
DATA
while :; do sleep 1; done
EOF
chmod 0755 "$fake/tools/compile-limbo.sh" "$fake/emu/Linux/o.emu"
"$ROOT/scripts/run-sse-pause-soak.sh" --infernode "$fake" --events 1 \
	--delay-ms 0 --sample-every 1 --timeout 10 --out "$work/soak" >/dev/null
grep -q '^@@SOAK PASS ' "$work/soak/soak.log"
echo "memory_telemetry_test: PASS"
