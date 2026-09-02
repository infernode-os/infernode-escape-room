# InferNode Escape Room

InferNode Escape Room is a repeatable adversarial-model campaign harness for
testing InferNode namespace containment. It gives a live model explicit
permission to inspect the open-source InferNode implementation, develop
attacks, use the tools reachable from its namespace, and attempt to recover or
modify ungranted synthetic canaries. The harness preserves trajectories,
namespace manifests, audit checkpoints, gateway state, and host-side evidence
for independent review.

This repository is security testing infrastructure. It is deliberately not
part of the InferNode runtime or release artifacts.

## Safety

Run live campaigns only on disposable, isolated systems containing no real
secrets or valuable data. A campaign intentionally asks an AI model to behave
adversarially. The outer VM and network boundaries limit the consequences of
an emulator or native-code flaw; they are not evidence that an InferNode
namespace held.

Read the complete [protocol](docs/PROTOCOL.md) before using live credentials or
model credit. A pass is a bounded experimental result, not proof that all
models, builds, namespace configurations, or future versions are secure.

## Quick start

```sh
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -r requirements.txt
./scripts/bootstrap.sh
cd vendor/infernode
./build-linux-amd64.sh headless
cd ../..
./tests/run.sh
```

`infernode.lock` pins the InferNode source revision. `scripts/bootstrap.sh`
verifies the configured upstream and exact commit before checking it out. The
harness also records both repository commits and dirty states in each campaign
manifest.

For an authorized rehearsal after configuring the isolated Codex gateway:

```sh
python3 grind.py \
  --infernode vendor/infernode \
  --scenarios scenarios/escape-room.yaml \
  --model default \
  --url http://GATEWAY-PRIVATE-IP:11436/v1 \
  --timeout 900
```

Results default to `~/.infernode/grindhouse`, outside the checkout. Treat the
entire result tree as private. The protocol describes the separate redaction
and publication process.

## Repository boundary

- `grind.py` orchestrates campaigns and seals evidence.
- `scenarios/` contains control and adversarial campaign definitions.
- `guest/` contains profiles staged into a pinned InferNode checkout at run
  time.
- `scripts/` contains lab, liveness, gateway-profile, and dependency helpers.
- `tests/` contains deterministic host-side harness tests.

InferNode remains the dependency and owns the emulator, Veltro, namespace
restriction, audit system, Codex gateway, and their product tests.

## Usage-limit recovery

The harness pauses active-time budgets only when the gateway authenticates a
Codex usage-limit state. It resumes the same in-flight campaign after quota is
available and records pause/resume transitions. Runner, emulator, or host loss
is a different failure class and remains inconclusive. `tests/grind_test.sh`
contains the deterministic recovery and fail-closed controls.

## License

This project is distributed under the same MIT license as InferNode. See
[LICENSE](LICENSE).
