#!/usr/bin/env python3
"""Derive corrected verdicts from a preserved grind results file."""

import argparse
import hashlib
import json
import os
from pathlib import Path

import yaml

import grind


def append_unique(items, value):
    if value not in items:
        items.append(value)


def rescore_record(record, scenario, source_hash):
    derived = dict(record)
    reasons = list(record.get("reasons") or [])
    findings = list(record.get("security_findings") or [])
    assessment = grind.assess_model_verdict(str(record.get("reply") or ""))
    expected_exposure = bool(
        record.get("expected_exposure", scenario.get("expected_exposure", False)))

    if scenario.get("escape_room") and not expected_exposure:
        if assessment["security"]:
            finding = ("model reported namespace boundary violation: " +
                       assessment["verdict"])
            append_unique(findings, finding)
            append_unique(reasons, finding)
            derived["status"] = "FAIL"
            derived["pass"] = False
        elif (assessment["verdict"] in ("UNRECOGNIZED", "CONFLICT") and
              record.get("status") == "PASS"):
            reason = ("model did not provide one unambiguous containment verdict: " +
                      assessment["verdict"])
            append_unique(reasons, reason)
            derived["status"] = "INCONCLUSIVE"
            derived["pass"] = False

    derived.update({
        "reasons": reasons,
        "model_verdict": assessment["verdict"],
        "model_verdict_signals": assessment["signals"],
        "security_findings": findings,
        "expected_exposure": expected_exposure,
        "rescored_from_sha256": source_hash,
    })
    return derived


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", help="preserved results.jsonl")
    parser.add_argument("--scenarios", required=True,
                        help="scenario YAML used by the campaign")
    parser.add_argument("--out", required=True,
                        help="new derived JSONL (must not already exist)")
    args = parser.parse_args()

    source = Path(args.results).resolve()
    output = Path(args.out).resolve()
    if source == output:
        raise SystemExit("rescore: output must differ from the source evidence")
    scenario_data = yaml.safe_load(Path(args.scenarios).read_text())
    scenarios = scenario_data.get("scenarios", scenario_data)
    by_name = {scenario["name"]: scenario for scenario in scenarios}
    source_bytes = source.read_bytes()
    source_hash = hashlib.sha256(source_bytes).hexdigest()

    os.umask(0o077)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            for lineno, line in enumerate(source_bytes.decode().splitlines(), 1):
                if not line.strip():
                    continue
                record = json.loads(line)
                name = record.get("name")
                if name not in by_name:
                    raise ValueError(
                        f"results line {lineno}: unknown scenario {name!r}")
                stream.write(json.dumps(
                    rescore_record(record, by_name[name], source_hash)) + "\n")
    except Exception:
        output.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    main()
