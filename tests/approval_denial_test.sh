#!/bin/sh
set -eu

ROOT=${ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
INFERNODE_ROOT=${INFERNODE_ROOT:-$ROOT/vendor/infernode}
EMU=$INFERNODE_ROOT/emu/Linux/o.emu
[ -x "$EMU" ] || { echo "approval_denial_test: SKIP (Linux emulator not built)"; exit 0; }

base=$INFERNODE_ROOT/tmp/infernode-escape-room
mkdir -p "$base"
cp "$ROOT/guest/deny-approvals" "$base/deny-approvals"
cp "$ROOT/guest/approval-denial-smoke" "$base/approval-denial-smoke"
chmod 700 "$base/deny-approvals" "$base/approval-denial-smoke"

cleanup() {
	rm -f "$base/deny-approvals" "$base/approval-denial-smoke"
}
trap cleanup EXIT HUP INT TERM

set +e
if command -v timeout >/dev/null 2>&1; then
	output=$(timeout 20 "$EMU" -c1 "-r$INFERNODE_ROOT" \
		sh /tmp/infernode-escape-room/approval-denial-smoke 2>&1)
	rc=$?
else
	output=$("$EMU" -c1 "-r$INFERNODE_ROOT" \
		sh /tmp/infernode-escape-room/approval-denial-smoke 2>&1)
	rc=$?
fi
set -e
echo "$output" | grep -q '^APPROVAL_DENIAL_SMOKE_PASS$' || {
	echo "$output"
	echo "approval_denial_test: FAIL (emulator exit $rc)" >&2
	exit 1
}
echo "approval_denial_test: PASS"
