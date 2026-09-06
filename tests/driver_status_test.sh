#!/bin/sh
# Model-free check of grind-driver's terminal activity-status predicate.

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EMU=$INFERNODE_ROOT/emu/Linux/o.emu
[ -x "$EMU" ] || { echo "driver_status_test: SKIP (Linux emulator not built)"; exit 0; }

terminal=$(sed -n '/^terminalstatus=(/p' "$ROOT/guest/grind-driver")
[ "$(printf '%s\n' "$terminal" | wc -l)" -eq 1 ] || {
	echo "driver_status_test: FAIL (terminal status declaration missing or repeated)"
	exit 1
}

name=driver-status-smoke-$$
relative=tmp/infernode-escape-room/$name
staged=$INFERNODE_ROOT/$relative
work=$(mktemp -d "${TMPDIR:-/tmp}/driver-status-test.XXXXXX")
mkdir -p "$(dirname "$staged")"
trap 'rm -f "$staged"; rm -rf "$work"' EXIT HUP INT TERM

{
	printf '%s\n' '#!/dis/sh.dis' 'load std' "$terminal"
	cat <<'EOF'
for (s in idle complete completed done failed error timeout closed hidden) {
	if {! ~ $s $terminalstatus} {
		echo DRIVER_STATUS_SMOKE_FAIL terminal $s
		exit
	}
}
for (s in grep read future-tool-state working thinking launching running active) {
	if {~ $s $terminalstatus} {
		echo DRIVER_STATUS_SMOKE_FAIL active $s
		exit
	}
}
echo DRIVER_STATUS_SMOKE_PASS
echo '@@GRIND done'
EOF
} > "$staged"
chmod 700 "$staged"

output=$(ROOT="$ROOT" INFERNODE_ROOT="$INFERNODE_ROOT" \
	DRIVER_INEMU="/$relative" WORK="$work" python3 - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
spec = importlib.util.spec_from_file_location("grind", root / "grind.py")
grind = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grind)
grind.configure_infernode(os.environ["INFERNODE_ROOT"])
grind.DRIVER_INEMU = os.environ["DRIVER_INEMU"]
grind.STAGE = Path(os.environ["WORK"])
grind.gateway_runtime_health = lambda _url: {"status": "ok"}
output, rc, completed, killed, active, wall, events = grind.run_emu(
    str(Path(os.environ["INFERNODE_ROOT"]) / "emu/Linux/o.emu"),
    30, "http://127.0.0.1:1/v1")
print(output, end="")
if not completed or killed:
    raise SystemExit("driver status smoke did not complete: "
                     f"rc={rc} completed={completed} killed={killed}")
PY
)
printf '%s\n' "$output" | grep -q '^DRIVER_STATUS_SMOKE_PASS$' || {
	printf '%s\n' "$output"
	echo "driver_status_test: FAIL (Inferno status predicate mismatch)"
	exit 1
}

echo "driver_status_test: PASS"
