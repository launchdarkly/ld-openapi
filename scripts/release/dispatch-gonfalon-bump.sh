#!/usr/bin/env bash
#
# Bumps gonfalon to a new api-client-go: dispatches gonfalon's own
# update-api-client-go.yml, which runs `make update-api-client-go` with
# gonfalon's CI setup and opens the PR, then waits for it so a failed bump fails
# this job too.
#
# Usage: dispatch-gonfalon-bump.sh VERSION [REVIEWER]
#
# Env:
#   GH_TOKEN      actions: write on launchdarkly/gonfalon: the
#                 ld-openapi-gonfalon-dispatch OctoSTS token (required)
#   WAIT_TIMEOUT  seconds to wait for the gonfalon run (default 3600)

set -euo pipefail

version=${1:?usage: dispatch-gonfalon-bump.sh VERSION [REVIEWER]}
reviewer=${2:-}

GONFALON=launchdarkly/gonfalon
WORKFLOW=update-api-client-go.yml
# Must match run-name in gonfalon's workflow: the dispatch API returns no run id.
RUN_NAME="Update api-client-go to ${version}"
WAIT_TIMEOUT=${WAIT_TIMEOUT:-3600}

fail() { echo "GONFALON BUMP FAILED: $*" >&2; exit 1; }
note() { echo "==> $*"; }

grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"${version}" || fail "VERSION must be bare semver (got '${version}')"

dispatched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
note "Dispatching ${GONFALON} ${WORKFLOW} for ${version}"
gh workflow run "${WORKFLOW}" --repo "${GONFALON}" --ref main \
  -f version="${version}" -f reviewer="${reviewer}"

# The run takes a few seconds to appear. Pick the newest run with this version's
# name created since the dispatch, so a rerun for the same version or an
# earlier run by hand is not mistaken for it.
run_id=""
for _ in $(seq 1 30); do
  run_id=$(gh run list --repo "${GONFALON}" --workflow "${WORKFLOW}" --event workflow_dispatch \
    --limit 20 --json databaseId,displayTitle,createdAt \
    --jq "[.[] | select(.displayTitle == \"${RUN_NAME}\" and .createdAt >= \"${dispatched_at}\")] | sort_by(.createdAt) | last | .databaseId // empty")
  [ -z "${run_id}" ] || break
  sleep 10
done
[ -n "${run_id}" ] || fail "no '${RUN_NAME}' run appeared in ${GONFALON} within 5 minutes of the dispatch"

url="https://github.com/${GONFALON}/actions/runs/${run_id}"
note "Waiting for ${url}"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "gonfalon api-client-go bump for ${version}: ${url}" >> "${GITHUB_STEP_SUMMARY}"

if ! timeout "${WAIT_TIMEOUT}" gh run watch "${run_id}" --repo "${GONFALON}" --exit-status --interval 30 >/dev/null; then
  fail "the gonfalon run failed, or did not finish within ${WAIT_TIMEOUT}s: ${url}
    Re-run it there once fixed; it opens or updates branch bump-api-client-go/${version}."
fi
note "Done; the bump PR is on branch bump-api-client-go/${version} in ${GONFALON}."
