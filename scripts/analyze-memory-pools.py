#!/usr/bin/env python3
"""Summarize Inferno /dev/memory samples captured by the harness."""

import argparse
import json
import re
import sys


MARKER = re.compile(r"^@@(?:MEMORY sample|SOAK memory)\b(.*)$")
FIELD = re.compile(r"([a-z_]+)=([^ ]+)")
POOLS = frozenset(("main", "heap", "image"))


def parse(stream):
    samples = []
    current = None
    for raw in stream:
        line = raw.strip()
        marker = MARKER.match(line)
        if marker:
            current = {"meta": dict(FIELD.findall(marker.group(1))), "pools": {}}
            samples.append(current)
            continue
        fields = line.split()
        if current is None or len(fields) != 8 or fields[-1] not in POOLS:
            continue
        try:
            values = [int(value) for value in fields[:7]]
        except ValueError:
            continue
        current["pools"][fields[-1]] = {
            "current": values[0], "limit": values[1], "high_water": values[2],
            "allocations": values[3], "frees": values[4],
            "breaks": values[5], "largest_free": values[6],
        }
    return [sample for sample in samples if sample["pools"]]


def summarize(samples):
    result = {"samples": len(samples), "pools": {}}
    for name in sorted(POOLS):
        readings = [sample["pools"][name] for sample in samples
                    if name in sample["pools"]]
        if not readings:
            continue
        current = [reading["current"] for reading in readings]
        active = [reading["allocations"] - reading["frees"] for reading in readings]
        result["pools"][name] = {
            "limit": readings[-1]["limit"],
            "start": current[0], "end": current[-1],
            "minimum": min(current), "peak": max(current),
            "delta": current[-1] - current[0],
            "active_allocations_start": active[0],
            "active_allocations_end": active[-1],
            "active_allocations_delta": active[-1] - active[0],
        }
    if samples:
        result["first_meta"] = samples[0]["meta"]
        result["last_meta"] = samples[-1]["meta"]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", help="telemetry log; stdin if omitted")
    parser.add_argument("--max-main-growth", type=int,
                        help="exit nonzero if main current grows by more bytes")
    args = parser.parse_args()
    if args.path:
        with open(args.path, encoding="utf-8", errors="replace") as stream:
            samples = parse(stream)
    else:
        samples = parse(sys.stdin)
    result = summarize(samples)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not samples:
        return 2
    if args.max_main_growth is not None and \
            result.get("pools", {}).get("main", {}).get("delta", 0) > \
            args.max_main_growth:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
