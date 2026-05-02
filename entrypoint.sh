#!/bin/bash
set -e

: "${ORG_NAME:?ORG_NAME is required}"
: "${ACCESS_TOKEN:?ACCESS_TOKEN is required}"

RUNNER_NAME="${RUNNER_NAME_PREFIX:-punter-runner}-$(hostname)-$RANDOM"
RUNNER_LABELS="${LABELS:-self-hosted,linux,docker}"
RUNNER_GROUP="${RUNNER_GROUP:-default}"
# Default to a per-container workdir so replicas don't fight over the same
# checkout tree when /tmp/runner is shared via a host bind-mount.
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/tmp/runner/$(hostname)/work}"

# Workdir is bind-mounted from the host and may be owned by root; the runner
# runs as the unprivileged `runner` user, so claim the tree on startup.
sudo mkdir -p "${RUNNER_WORKDIR}"
sudo chown -R runner:runner "${RUNNER_WORKDIR}" "$(dirname "${RUNNER_WORKDIR}")"

API_BASE="https://api.github.com/orgs/${ORG_NAME}/actions/runners"

echo "Fetching registration token for org: ${ORG_NAME}"
REG_TOKEN=$(curl -fsS -X POST \
    -H "Authorization: token ${ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${API_BASE}/registration-token" | jq -r .token)

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
    echo "ERROR: Failed to fetch registration token. Check ACCESS_TOKEN permissions and ORG_NAME."
    exit 1
fi

cd /actions-runner

./config.sh \
    --url "https://github.com/${ORG_NAME}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --runnergroup "${RUNNER_GROUP}" \
    --work "${RUNNER_WORKDIR}" \
    --unattended \
    --replace \
    --ephemeral

# Graceful deregistration on container stop
cleanup() {
    echo "Deregistering runner..."
    REMOVE_TOKEN=$(curl -fsS -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API_BASE}/remove-token" | jq -r .token)
    ./config.sh remove --token "${REMOVE_TOKEN}" || true
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
