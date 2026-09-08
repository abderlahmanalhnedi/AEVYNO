# AEVYNO Self-Hosted macOS CI

AEVYNO uses a repository-scoped self-hosted macOS runner so native Xcode, iOS Simulator and tvOS
Simulator validation can run without GitHub-hosted macOS billing.

## Security boundary

- The runner is repository-scoped to `abderlahmanalhnedi/AEVYNO`.
- CI jobs require the custom `aevyno` label in addition to the default self-hosted macOS/ARM64 labels.
- Pull-request jobs are restricted to branches whose head repository is AEVYNO itself. Do not run
  untrusted fork pull requests on this machine.
- The workflow keeps `contents: read`, disables persisted checkout credentials, and uses no signing
  identity, Apple ID or IPTV/provider credential.
- The runner is installed outside iCloud Drive at `~/actions-runner/AEVYNO` by default.

## One-time setup

The repository contains `scripts/setup-aevyno-self-hosted-runner.sh`.

Run it as the macOS user that owns the development environment:

```bash
bash scripts/setup-aevyno-self-hosted-runner.sh
```

The script:

1. verifies GitHub CLI authentication;
2. downloads the latest official GitHub Actions runner for the Mac architecture;
3. verifies the GitHub-provided SHA-256 digest when available;
4. obtains a short-lived repository registration token through `gh api`;
5. registers `AEVYNO-MacBook-Air` with the custom `aevyno` label; and
6. installs and starts the runner as a per-user launchd service.

No registration token is written to the repository.

## Requirements

- macOS on the development Mac.
- `gh` authenticated as a repository administrator.
- Xcode 26.6 installed at either `/Applications/Xcode.app` or
  `/Applications/Xcode_26.6.app`.
- tvOS 26.5 Apple TV 4K (3rd generation) Simulator installed.
- The Mac must be powered on and the runner service available when CI is expected to run.

## Verify runner status

```bash
gh api repos/abderlahmanalhnedi/AEVYNO/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

Expected runner labels include:

- `self-hosted`
- `macOS`
- `ARM64`
- `aevyno`

## Stop or start the service

```bash
cd ~/actions-runner/AEVYNO
./svc.sh stop
./svc.sh start
./svc.sh status
```

The self-hosted runner does not replace physical Apple TV validation.
