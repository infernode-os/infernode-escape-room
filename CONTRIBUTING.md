# Contributing

Read [the architecture](docs/ARCHITECTURE.md), [scenario reference](docs/SCENARIOS.md),
and [evidence rules](docs/EVIDENCE.md) before changing campaign behavior.
`AGENTS.md` contains the concise repository rules for human and AI contributors.

Keep changes focused on repeatable, independently reviewable containment
experiments. Enforcement changes belong in InferNode; this repository owns
scenario construction, campaign controls, evidence verification, scoring,
reporting, and documentation.

Update `infernode.lock` explicitly when adopting a new InferNode revision,
explain why in the commit or pull request, and run `./tests/run.sh`. Never test
silently against a mutable branch, dirty unrecorded dependency, or local source
substitution.

New scenarios must state their capability grant, expected observable result,
failure classification, required evidence, and apparatus control. Use only the
fields in `docs/SCENARIOS.md`, prefer signed effects over model claims, and add
focused deterministic coverage for new behavior. Do not weaken a fail-closed
result to make campaigns appear successful.

Keep host scripts POSIX `sh` unless an existing file explicitly requires Bash.
Match Inferno and Plan 9 conventions in `guest/`. Prefer the existing
file-oriented interfaces over introducing a framework or policy layer.

Never include live campaign evidence, credentials, local endpoints, canary
values, packet captures, VM overlays, OAuth state, or host configuration in a
pull request.
