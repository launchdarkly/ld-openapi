#!/usr/bin/env bash
#
# Runbook step 9: verify the release actually landed everywhere, instead of
# trusting that someone remembered to spot-check a repo.
#
# Usage: verify-published.sh VERSION
#
# Hard checks fail the job. Soft checks only warn: Maven Central's sync from the
# publishing portal to repo1 can lag well past a sensible CI timeout, so a miss
# there means "check later", not "the release is broken".

set -euo pipefail

version=${1:?usage: verify-published.sh VERSION}
major=${version%%.*}

POLL_TIMEOUT=${POLL_TIMEOUT:-600}
POLL_INTERVAL=${POLL_INTERVAL:-20}

failures=()
warnings=()

# poll NAME MODE URL
#   MODE is "hard" or "soft".
poll() {
  local name=$1 mode=$2 url=$3
  local deadline=$(( $(date +%s) + POLL_TIMEOUT ))

  echo "==> ${name}"
  while :; do
    local code
    code=$(curl -s -o /dev/null -L -w '%{http_code}' "${url}" || echo 000)
    if [ "${code}" = "200" ]; then
      echo "    published (${url})"
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      if [ "${mode}" = "hard" ]; then
        failures+=("${name} — last HTTP ${code} from ${url}")
        echo "    NOT FOUND after ${POLL_TIMEOUT}s (HTTP ${code})"
      else
        warnings+=("${name} — not visible yet (HTTP ${code}); registry sync may still be in flight")
        echo "    not visible yet (HTTP ${code}) — soft check, continuing"
      fi
      return 0
    fi
    sleep "${POLL_INTERVAL}"
  done
}

poll "PyPI launchdarkly-api"                hard "https://pypi.org/pypi/launchdarkly-api/${version}/json"
poll "RubyGems launchdarkly_api"            hard "https://rubygems.org/api/v2/rubygems/launchdarkly_api/versions/${version}.json"
poll "npm launchdarkly-api-typescript"      hard "https://registry.npmjs.org/launchdarkly-api-typescript/${version}"
# Soft, deliberately. Go has no publish step — the git tag IS the release, and the
# tag is checked below. proxy.golang.org is a demand-populated cache that also
# caches negative lookups, so a `go get` for the version before it existed (a dry
# run, say) makes it serve "unknown revision" for a while afterwards. That happened
# on 24.0.0 and failed this job on an otherwise complete release.
poll "Go module proxy api-client-go/v${major}" soft "https://proxy.golang.org/github.com/launchdarkly/api-client-go/v${major}/@v/v${version}.info"
poll "Maven Central com.launchdarkly:api-client" soft "https://repo1.maven.org/maven2/com/launchdarkly/api-client/${version}/api-client-${version}.pom"

# Tags on the client repos, checking only what exists at THIS point in the graph.
# `make push` tags Go as v<version> but the other four as a bare <version>; their
# v<version> tag is created later, by the create-release job, which runs after
# this one. Checking v<version> everywhere would fail four repos on every healthy
# release and stop the run before create-release ever got the chance.
echo "==> client repo tags"
for repo in api-client-go api-client-java api-client-python api-client-ruby api-client-typescript; do
  if [ "${repo}" = "api-client-go" ]; then ref="v${version}"; else ref="${version}"; fi
  if gh api "repos/launchdarkly/${repo}/git/ref/tags/${ref}" >/dev/null 2>&1; then
    echo "    launchdarkly/${repo} ${ref}"
  else
    failures+=("launchdarkly/${repo} has no ${ref} tag")
    echo "    launchdarkly/${repo} MISSING ${ref}"
  fi
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Publish verification for ${version}"
    if [ ${#failures[@]} -eq 0 ]; then
      echo
      echo "All hard checks passed."
    else
      echo
      echo "**Failures**"
      printf -- '- %s\n' "${failures[@]}"
    fi
    if [ ${#warnings[@]} -gt 0 ]; then
      echo
      echo "**Warnings**"
      printf -- '- %s\n' "${warnings[@]}"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [ ${#warnings[@]} -gt 0 ]; then
  printf 'WARNING: %s\n' "${warnings[@]}" >&2
fi

if [ ${#failures[@]} -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}" >&2
  echo >&2
  echo "Re-running the release requires deleting the tags it already created (both X.Y.Z and vX.Y.Z on non-Go repos) or dispatching with force=true." >&2
  exit 1
fi

echo "All hard checks passed for ${version}."
