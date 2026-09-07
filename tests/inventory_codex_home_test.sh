#!/bin/sh
set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-inventory-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
chmod 700 "$work"
printf '%s\n' 'oauth-secret-must-not-appear' > "$work/auth.json"
printf '%s\n' 'host-installation-id-must-not-appear' > "$work/installation_id"
mkdir "$work/sessions"
printf '%s\n' 'session-state' > "$work/sessions/one.jsonl"
chmod 600 "$work/auth.json" "$work/installation_id" "$work/sessions/one.jsonl"

"$ROOT/scripts/inventory-codex-home.py" "$work" > "$work.inventory"

python3 - "$work.inventory" <<'PY'
import json
import sys

raw = open(sys.argv[1]).read()
assert "oauth-secret-must-not-appear" not in raw
assert "host-installation-id-must-not-appear" not in raw
value = json.loads(raw)
assert value["schema"] == "infernode-escape-room/codex-home-inventory/v1"
entries = {entry["path"]: entry for entry in value["entries"]}
assert entries["auth.json"]["content"] == "redacted"
assert "sha256" not in entries["auth.json"]
assert entries["installation_id"]["content"] == "redacted"
assert "sha256" in entries["sessions/one.jsonl"]
assert value["credential_files"] == 2
assert value["persistent_cli_state_files"] == 1
print("inventory_codex_home_test: PASS")
PY
