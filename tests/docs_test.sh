#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
documents = [
    root / "README.md",
    root / "AGENTS.md",
    root / "CONTRIBUTING.md",
    root / "SECURITY.md",
    *sorted((root / "docs").glob("*.md")),
]

missing = []
link_re = re.compile(r"(?<!!)\[[^]]*\]\(([^)]+)\)")
for document in documents:
    text = document.read_text()
    for raw in link_re.findall(text):
        target = raw.split(maxsplit=1)[0].strip("<>")
        if not target or target.startswith(("#", "http://", "https://", "mailto:")):
            continue
        path_text = target.split("#", 1)[0]
        if path_text and not (document.parent / path_text).resolve().exists():
            missing.append(f"{document.relative_to(root)} -> {target}")
assert not missing, "missing local documentation links:\n" + "\n".join(missing)

reference = (root / "docs" / "SCENARIOS.md").read_text()
keys = {"gateway", "scenarios"}
for scenario_file in sorted((root / "scenarios").glob("*.yaml")):
    suite = yaml.safe_load(scenario_file.read_text())
    assert isinstance(suite, dict), scenario_file
    keys.update((suite.get("gateway") or {}).keys())
    for scenario in suite.get("scenarios", []):
        keys.update(scenario.keys())
        keys.update((scenario.get("namespace") or {}).keys())
        keys.update((scenario.get("expects") or {}).keys())
        keys.update((scenario.get("forbid") or {}).keys())
source = (root / "grind.py").read_text()
for receiver in ("sc", "exp", "forbid", "requirements", "raw"):
    keys.update(re.findall(rf'{receiver}\.get\("([^"]+)"', source))
keys.discard("run_id")
undocumented = sorted(key for key in keys if f"`{key}`" not in reference)
assert not undocumented, "scenario keys absent from docs/SCENARIOS.md: " + ", ".join(undocumented)

readme = (root / "README.md").read_text()
agents = (root / "AGENTS.md").read_text()
for name in ("ARCHITECTURE.md", "SCENARIOS.md", "RUNBOOKS.md", "EVIDENCE.md", "PROTOCOL.md"):
    assert name in readme, f"README.md does not link {name}"
    assert name in agents, f"AGENTS.md does not direct agents to {name}"

options = set(re.findall(r'ap\.add_argument\("(--[a-z-]+)"', source))
missing_options = sorted(option for option in options if f"`{option}" not in readme)
assert not missing_options, "CLI options absent from README.md: " + ", ".join(missing_options)

header = "\n".join(source.splitlines()[:30])
assert "--keep" not in header, "grind.py header advertises removed --keep option"
assert "claude-gate by default" not in header, "grind.py header advertises stale gateway"

print("docs_test: PASS")
PY
