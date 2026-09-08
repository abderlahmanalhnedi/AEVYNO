#!/usr/bin/env bash
set -euo pipefail

REPO="abderlahmanalhnedi/AEVYNO"
RUNNER_NAME="${AEVYNO_RUNNER_NAME:-AEVYNO-MacBook-Air}"
RUNNER_DIR="${AEVYNO_RUNNER_DIR:-$HOME/actions-runner/AEVYNO}"
CUSTOM_LABEL="aevyno"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is required."
command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"

arch="$(uname -m)"
case "$arch" in
  arm64) asset_prefix="actions-runner-osx-arm64-" ;;
  x86_64) asset_prefix="actions-runner-osx-x64-" ;;
  *) fail "Unsupported macOS architecture: $arch" ;;
esac

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ -f .runner ]]; then
  echo "Runner is already configured in $RUNNER_DIR."
else
  if find . -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    fail "$RUNNER_DIR is not empty and is not an existing runner directory."
  fi

  echo "Resolving latest official GitHub Actions runner release..."
  asset_line="$(
    gh api repos/actions/runner/releases/latest \
      --jq ".assets[] | select(.name | startswith(\"$asset_prefix\")) | select(.name | endswith(\".tar.gz\")) | [.browser_download_url, (.digest // \"\")] | @tsv" \
      | head -n 1
  )"

  [[ -n "$asset_line" ]] || fail "Could not resolve a compatible runner package."

  IFS=$'\t' read -r asset_url asset_digest <<< "$asset_line"
  archive="$(mktemp -t aevyno-actions-runner).tar.gz"
  trap 'rm -f "$archive"' EXIT

  echo "Downloading official GitHub Actions runner..."
  curl --fail --location --retry 3 --output "$archive" "$asset_url"

  if [[ "$asset_digest" == sha256:* ]]; then
    expected="${asset_digest#sha256:}"
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || fail "Runner package SHA-256 verification failed."
    echo "Runner package SHA-256 verified."
  else
    echo "Warning: GitHub did not expose an asset digest; continuing with the official GitHub release URL."
  fi

  tar -xzf "$archive"

  echo "Requesting a short-lived repository runner registration token..."
  registration_token="$(
    gh api --method POST "repos/$REPO/actions/runners/registration-token" --jq '.token'
  )"
  [[ -n "$registration_token" ]] || fail "Could not obtain a runner registration token."

  ./config.sh \
    --unattended \
    --replace \
    --url "https://github.com/$REPO" \
    --token "$registration_token" \
    --name "$RUNNER_NAME" \
    --labels "$CUSTOM_LABEL" \
    --work "_work"

  unset registration_token
fi

echo "Installing the runner as a per-user macOS launchd service..."

# svc.sh status can report "not installed" while still exiting successfully on macOS.
# Use the runner's .service marker instead of status exit code to decide whether an
# existing launchd service must be removed first.
if [[ -f .service ]]; then
  ./svc.sh stop >/dev/null 2>&1 || true
  ./svc.sh uninstall >/dev/null 2>&1 || true
fi

./svc.sh install
./svc.sh start
./svc.sh status

echo
echo "Repository runner status:"
runner_status="$(
  gh api "repos/$REPO/actions/runners" \
    --jq ".runners[] | select(.name == \"$RUNNER_NAME\") | .status"
)"

gh api "repos/$REPO/actions/runners" \
  --jq ".runners[] | select(.name == \"$RUNNER_NAME\") | {name, status, busy, labels: [.labels[].name]}"

if [[ "$runner_status" != "online" ]]; then
  echo
  echo "The runner is registered but not online yet."
  echo "Inspect launchd state with:"
  echo "  cat .service"
  echo "  ./svc.sh status"
  echo "  launchctl print gui/$(id -u)/$(basename \"$(cat .service)\" .plist)"
  exit 1
fi

echo
echo "AEVYNO self-hosted runner setup is complete and online."
echo "The Mac must be powered on and logged into this user account for CI jobs to run."
