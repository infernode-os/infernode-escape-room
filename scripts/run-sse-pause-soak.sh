#!/bin/sh
set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EVENTS=10000
DELAY_MS=1
SAMPLE_EVERY=1000
MAIN_POOL=1024m
TIMEOUT=900
OUT=${OUT:-$ROOT/results/sse-pause-soak}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--infernode) INFERNODE_ROOT=$2; shift 2 ;;
	--events) EVENTS=$2; shift 2 ;;
	--delay-ms) DELAY_MS=$2; shift 2 ;;
	--sample-every) SAMPLE_EVERY=$2; shift 2 ;;
	--main-pool) MAIN_POOL=$2; shift 2 ;;
	--timeout) TIMEOUT=$2; shift 2 ;;
	--out) OUT=$2; shift 2 ;;
	-h|--help)
		echo "usage: $0 [--infernode PATH] [--events N] [--delay-ms N] [--sample-every N] [--main-pool SIZE] [--timeout SEC] [--out DIR]"
		exit 0 ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

case "$EVENTS:$DELAY_MS:$SAMPLE_EVERY:$TIMEOUT" in
	*[!0-9:]*) echo "event, delay, sample, and timeout values must be integers" >&2; exit 2 ;;
esac
[ "$EVENTS" -gt 0 ] && [ "$SAMPLE_EVERY" -gt 0 ] && [ "$TIMEOUT" -gt 0 ] || {
	echo "events, sample-every, and timeout must be positive" >&2
	exit 2
}
printf '%s\n' "$MAIN_POOL" | grep -Eq '^[1-9][0-9]*[kKmMgG]?$' || {
	echo "invalid main pool size: $MAIN_POOL" >&2
	exit 2
}

test -f "$INFERNODE_ROOT/mkconfig" || {
	echo "not an InferNode checkout: $INFERNODE_ROOT" >&2
	exit 2
}
EMU=
for candidate in "$INFERNODE_ROOT/emu/MacOSX/o.emu" "$INFERNODE_ROOT/emu/Linux/o.emu"; do
	if [ -x "$candidate" ]; then EMU=$candidate; break; fi
done
test -n "$EMU" || { echo "no built emulator under $INFERNODE_ROOT/emu" >&2; exit 2; }

umask 077
mkdir -p "$OUT" "$INFERNODE_ROOT/tmp/escape-room-soak"
cp "$ROOT/guest/sse-pause-soak.b" "$INFERNODE_ROOT/tmp/escape-room-soak/sse-pause-soak.b"
"$INFERNODE_ROOT/tools/compile-limbo.sh" \
	"$INFERNODE_ROOT/tmp/escape-room-soak/sse-pause-soak.b"

LOG=$OUT/soak.log
PID=
stop_emulator()
{
	[ -n "$PID" ] || return 0
	kill -0 "$PID" 2>/dev/null || return 0
	kill -TERM "$PID" 2>/dev/null || true
	i=0
	while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 10 ]; do
		sleep 1
		i=$((i + 1))
	done
	if kill -0 "$PID" 2>/dev/null; then
		kill -KILL "$PID" 2>/dev/null || true
	fi
}
trap 'stop_emulator' EXIT
trap 'exit 1' HUP INT TERM

"$EMU" -c1 -pheap=1024m -pmain="$MAIN_POOL" -pimage=1024m \
	-r"$INFERNODE_ROOT" /dis/tests/escape-sse-pause-soak.dis \
	"$EVENTS" "$DELAY_MS" "$SAMPLE_EVERY" > "$LOG" 2>&1 &
PID=$!

deadline=$(($(date +%s) + TIMEOUT))
passed=false
while [ "$(date +%s)" -lt "$deadline" ]; do
	if grep -q '^@@SOAK PASS ' "$LOG" 2>/dev/null; then
		passed=true
		break
	fi
	if ! kill -0 "$PID" 2>/dev/null; then
		break
	fi
	sleep 1
done

stop_emulator
wait "$PID" 2>/dev/null || true
PID=
chmod 0600 "$LOG"
python3 "$ROOT/scripts/analyze-memory-pools.py" "$LOG" > "$OUT/summary.json"
chmod 0600 "$OUT/summary.json"
cat "$OUT/summary.json"
[ "$passed" = true ] || {
	echo "soak did not reach its PASS marker; see $LOG" >&2
	exit 1
}
