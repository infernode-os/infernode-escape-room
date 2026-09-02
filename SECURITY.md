# Security Policy

Do not use public issues for vulnerabilities that could enable an InferNode
namespace escape, emulator compromise, credential exposure, or evidence
forgery. Report them through the private security advisory facility for the
affected GitHub repository.

This harness executes intentionally adversarial model output. Run it only on
systems you own or are explicitly authorized to test, using disposable hosts,
synthetic canaries, isolated credentials, and the network boundaries in
[docs/PROTOCOL.md](docs/PROTOCOL.md).

Campaign artifacts can contain sensitive prompts, trajectories, host paths,
audit records, and plaintext canaries. Keep them private unless the protocol's
redaction and post-redaction canary scan both succeed.
