#!/usr/bin/env bash
#
# Runbook steps 10 and 12, as a single downstream change:
#   10. rename gonfalon's [Unreleased] changelog heading to the released version
#       and open a fresh empty [Unreleased] above it
#   12. bump the api-client-go version gonfalon depends on
#
# Runs from the root of a gonfalon checkout — pr-downstream clones the downstream
# repo into a subdirectory and runs update-command there, so this script is
# invoked by absolute path out of the ld-openapi-private workspace.
#
# Usage: gonfalon-update.sh VERSION [RELEASE_DATE]
#
# The dependency bump itself lives in gonfalon as `make update-api-client-go`,
# beside the imports it rewrites — a major bump moves the module path
# (api-client-go/vN) and has to move Go sources, BUILD.bazel labels, and
# MODULE.bazel together. This script only drives it and handles the changelog.

set -euo pipefail

version=${1:?usage: gonfalon-update.sh VERSION [RELEASE_DATE]}
release_date=${2:-$(date -u +%Y-%m-%d)}

CHANGELOG=apidocs/CHANGELOG.md

fail() { echo "gonfalon-update FAILED: $*" >&2; exit 1; }
note() { echo "==> $*"; }

[ -f go.mod ] || fail "no go.mod here — expected to run from the gonfalon repo root (pwd=$(pwd))"
[ -f "${CHANGELOG}" ] || fail "${CHANGELOG} not found"
grep -q '^update-api-client-go:' Makefile || \
  fail "gonfalon has no 'update-api-client-go' make target — it may have been renamed"

# --- Step 10: changelog ------------------------------------------------------
note "Renaming [Unreleased] to [${version}] - ${release_date} in ${CHANGELOG}"
grep -qx '## \[Unreleased\]' "${CHANGELOG}" || \
  fail "no '## [Unreleased]' heading in ${CHANGELOG}; it may have been renamed already"

# Without this, a retried release re-renames the freshly created [Unreleased]
# heading and leaves two [VERSION] sections behind.
grep -qE "^## \[${version}\]" "${CHANGELOG}" && \
  fail "${CHANGELOG} already has a '## [${version}]' section — this release was already recorded in gonfalon"

awk -v version="${version}" -v date="${release_date}" '
  !done && /^## \[Unreleased\]$/ {
    print "## [Unreleased]"
    print ""
    print "## [" version "] - " date
    done = 1
    next
  }
  { print }
' "${CHANGELOG}" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "${CHANGELOG}"

# --- Step 12: api-client-go ---------------------------------------------------
note "make update-api-client-go API_CLIENT_GO_VERSION=${version}"
make update-api-client-go "API_CLIENT_GO_VERSION=${version}"

# Guard against a silent no-op: if nothing changed, the PR would be empty and the
# release would look complete while gonfalon still points at the old client.
if git diff --quiet; then
  fail "no changes produced — the changelog rewrite and dependency bump both no-opped"
fi

note "Done. Changed files:"
git diff --name-only | sed 's/^/    /'
