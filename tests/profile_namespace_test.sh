#!/bin/sh
# Model-free regression for the exact profile-matrix namespace construction.

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EMU=$INFERNODE_ROOT/emu/Linux/o.emu
[ -x "$EMU" ] || { echo "profile_namespace_test: SKIP (Linux emulator not built)"; exit 0; }
[ -f "$INFERNODE_ROOT/dis/veltro/tools9p.dis" ] || {
	echo "profile_namespace_test: SKIP (InferNode bytecode not built)"
	exit 0
}

name=profile-namespace-smoke-test-$$
staged=$INFERNODE_ROOT/tmp/infernode-escape-room/$name
work=$(mktemp -d "${TMPDIR:-/tmp}/profile-namespace-test.XXXXXX")
mkdir -p "$(dirname "$staged")"
trap 'rm -f "$staged"; rm -rf "$work"' EXIT HUP INT TERM
cp "$ROOT/guest/profile-namespace-smoke" "$staged"
chmod 700 "$staged"

if output=$(ROOT="$ROOT" INFERNODE_ROOT="$INFERNODE_ROOT" \
	DRIVER_INEMU="/tmp/infernode-escape-room/$name" WORK="$work" \
	python3 - <<'PY'
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
    raise SystemExit("profile namespace driver did not complete: "
                     f"rc={rc} completed={completed} killed={killed}")
PY
); then
	rc=0
else
	rc=$?
fi
[ "$rc" -eq 0 ] || {
	echo "$output"
	echo "profile_namespace_test: FAIL (driver rc=$rc)"
	exit 1
}

echo "$output" | grep -q '^PROFILE_NAMESPACE_SMOKE_PASS$' || {
	echo "$output"
	echo "profile_namespace_test: FAIL (exact namespace did not materialize)"
	exit 1
}
echo "$output" | grep -q '^nsaudit=caps' || {
	echo "$output"
	echo "profile_namespace_test: FAIL (live nsaudit report missing)"
	exit 1
}
if echo "$output" | grep -q 'severity=high'; then
	echo "$output"
	echo "profile_namespace_test: FAIL (high-severity nsaudit finding)"
	exit 1
fi

echo "profile_namespace_test: PASS"
