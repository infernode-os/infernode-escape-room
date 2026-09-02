#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

for test in \
	"$ROOT/tests/grind_test.sh" \
	"$ROOT/tests/escape_lab_test.sh" \
	"$ROOT/tests/emu_liveness_test.sh" \
	"$ROOT/tests/serve_agent_test.sh"
do
	"$test"
done
