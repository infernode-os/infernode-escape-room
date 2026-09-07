#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

for test in \
	"$ROOT/tests/grind_test.sh" \
	"$ROOT/tests/quota_proxy_test.sh" \
	"$ROOT/tests/inventory_codex_home_test.sh" \
	"$ROOT/tests/approval_denial_test.sh" \
	"$ROOT/tests/driver_status_test.sh" \
	"$ROOT/tests/prepare_codex_home_test.sh" \
	"$ROOT/tests/escape_lab_test.sh" \
	"$ROOT/tests/emu_liveness_test.sh" \
	"$ROOT/tests/profile_namespace_test.sh" \
	"$ROOT/tests/namespace_driver_test.sh" \
	"$ROOT/tests/serve_agent_test.sh"
do
	"$test"
done
