# Repository Guidelines

## Purpose and trust boundary

This repository contains adversarial testing infrastructure for InferNode. It
must never be packaged into InferNode releases. InferNode is an external,
pinned dependency described by `infernode.lock`; do not silently test against a
mutable branch or an unrecorded local tree.

Treat every live-model response and generated file as hostile input. Campaigns
must fail closed when audit coverage, provenance, emulator liveness, canary
verification, or gateway qualification is incomplete.

## Structure

Campaign orchestration belongs in `grind.py`, scenario definitions in
`scenarios/`, in-emulator files in `guest/`, host helpers in `scripts/`, and
deterministic checks in `tests/`. Enforcement belongs in InferNode itself, not
in this harness.

## Start here

Read documentation according to the task:

- `README.md`: purpose, safety boundary, setup, and command index.
- `docs/ARCHITECTURE.md`: machines, containment layers, trust boundaries, and
  campaign lifecycle.
- `docs/SCENARIOS.md`: complete suite, namespace, expectation, and forbid field
  reference.
- `docs/RUNBOOKS.md`: deterministic setup, rehearsal, authoritative campaigns,
  quota/liveness, incident response, and publication review.
- `docs/EVIDENCE.md`: attempt classes, verdict table, artifacts, and review
  checklist.
- `docs/PROTOCOL.md`: normative authoritative experiment protocol.

Before changing code, identify whether the defect is in enforcement or
measurement. Changes to `restrictns()`, namespace semantics, descriptor or
process isolation, and production services belong in the pinned InferNode
repository. Changes to scenario construction, campaign controls, evidence,
scoring, and reporting belong here.

The scenario loader currently validates `namespace` declarations strictly but
does not reject every unknown outer or scoring key. Use only fields documented
in `docs/SCENARIOS.md` and add focused tests when introducing one.

## Development

Use `./scripts/bootstrap.sh` to obtain the pinned InferNode revision. Install
Python dependencies from `requirements.txt`, then run `./tests/run.sh`.
Behavior changes require focused deterministic tests. Live model runs do not
replace those tests.

Shell scripts should remain POSIX `sh` unless an existing script explicitly
requires Bash. Match Inferno and Plan 9 conventions in guest profiles. Prefer
simple file-oriented protocols over new frameworks or policy layers.

## Evidence and credentials

Never commit campaign output, canary material, packet captures, VM overlays,
OAuth state, API keys, endpoint configuration, or local host details. Evidence
is private at creation and may be published only through the protocol's
redaction and canary-scan process.

## Security priorities

Review threats in this order: adversarial or prompt-injected AI agents,
sophisticated remote automated attackers, then communication and cryptographic
protocol attacks. Preserve truthful namespace restriction and direct,
auditable evidence.
