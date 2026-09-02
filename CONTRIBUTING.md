# Contributing

Keep changes focused on repeatable, independently reviewable containment
experiments. Update `infernode.lock` explicitly when adopting a new InferNode
revision, explain why in the commit or pull request, and run `./tests/run.sh`.

New scenarios must state their capability grant, expected observable result,
failure classification, and required evidence. Do not weaken a fail-closed
result to make campaigns appear successful.

Never include live campaign evidence, credentials, local endpoints, canary
values, or host configuration in a pull request.
