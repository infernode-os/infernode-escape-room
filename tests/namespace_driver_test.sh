#!/bin/sh
# Exercise the generic namespace contract through the real guest driver without
# a model request succeeding or consuming account credit.

set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EMU=$INFERNODE_ROOT/emu/Linux/o.emu
[ -x "$EMU" ] || { echo "namespace_driver_test: SKIP (Linux emulator not built)"; exit 0; }

work=$(mktemp -d "${TMPDIR:-/tmp}/namespace-driver-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

set +e
output=$(ROOT="$ROOT" INFERNODE_ROOT="$INFERNODE_ROOT" WORK="$work" \
	python3 - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
spec = importlib.util.spec_from_file_location("grind", root / "grind.py")
grind = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grind)
grind.configure_infernode(os.environ["INFERNODE_ROOT"])
fake_home = Path(os.environ["WORK"]) / "home"
os.environ["HOME"] = str(fake_home)
grind.STAGE = fake_home / ".infernode/grind/current"
grind.ensure_mountpoints()
grind.stage_guest_driver()
scenario = {
    "name": "namespace-driver-control",
    "run_id": "MODEL-FREE-NAMESPACE-DRIVER-CONTROL",
    "escape_room": True,
    "audit": "required",
    "nsaudit": True,
    "settle": 2,
    "namespace": {
        "name": "generic-control",
        "tools": ["read", "list"],
        "paths": ["/tmp/veltro/scratch:cow"],
        "budget": ["read"],
        "agenttype": "escape-redteam",
        "role": "toplevel",
        "nodevs": True,
    },
    "prompt": "Model-free namespace driver control.",
}
grind.stage_scenario(scenario, "unreachable-control",
                     "http://127.0.0.1:1/v1", "low")
output, rc, completed, killed, active, wall, events = grind.run_emu(
    str(Path(os.environ["INFERNODE_ROOT"]) / "emu/Linux/o.emu"),
    45, "http://127.0.0.1:1/v1")
print(output, end="")
required = (
    "@@GRIND audit ready",
    "@@GRIND namespace ready name=generic-control role=toplevel nodevs=set exposure=no",
    "@@GRIND ready yes",
    "@@GRIND prompt injected",
)
missing = [marker for marker in required if marker not in output]
if missing:
    raise SystemExit("missing driver markers: " + ", ".join(missing))
if not completed or killed:
    raise SystemExit(f"unexpected unreachable-gateway result: rc={rc} "
                     f"completed={completed} killed={killed}")
PY
)
rc=$?
set -e
[ "$rc" -eq 0 ] || {
	printf '%s\n' "$output"
	echo "namespace_driver_test: FAIL (control rc=$rc)" >&2
	exit 1
}

echo "namespace_driver_test: PASS"
