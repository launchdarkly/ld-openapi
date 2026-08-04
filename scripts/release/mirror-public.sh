#!/usr/bin/env bash
#
# Runbook step 11: squash-mirror this private repo onto the public launchdarkly/ld-openapi.
#
# Usage: mirror-public.sh VERSION
#
# Env:
#   BOT_TOKEN   the releaser token, used for both repos (required)
#   DRY_RUN     true = `git push --dry-run`
#
# One token covers both sides: public ld-openapi and this repo both grant
# "sa-release-bots" = "Releaser" in terraform, the same grant the api-client-*
# repos use for the pushes `make push` already does every release.
#
# This makes private-repo content public and is not practically reversible, so it
# deliberately does NOT resolve conflicts: the runbook's guidance is "generally
# I'd choose the private repo one, but use your discretion", which is a human
# decision. On conflict this aborts and leaves the release otherwise complete.

set -euo pipefail

version=${1:?usage: mirror-public.sh VERSION}
: "${BOT_TOKEN:?BOT_TOKEN is required}"

PUBLIC_REPO=launchdarkly/ld-openapi
PRIVATE_REPO=launchdarkly/ld-openapi-private

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

note() { echo "==> $*"; }
fail() { echo "MIRROR FAILED: $*" >&2; exit 1; }

note "Cloning ${PUBLIC_REPO}"
git clone --quiet "https://x-access-token:${BOT_TOKEN}@github.com/${PUBLIC_REPO}.git" "${workdir}/public"
cd "${workdir}/public"

git config user.name LaunchDarklyReleaseBot
git config user.email launchdarklyreleasebot@launchdarkly.com

git remote add private "https://x-access-token:${BOT_TOKEN}@github.com/${PRIVATE_REPO}.git"
git fetch --quiet private main

if git diff --quiet HEAD private/main; then
  note "Public repo already matches private main — nothing to mirror."
  exit 0
fi

note "Files that will change on ${PUBLIC_REPO}"
git diff --name-status HEAD private/main | sed 's/^/    /'

if ! git merge --squash private/main; then
  conflicts=$(git diff --name-only --diff-filter=U || true)
  fail "merge conflicts while squashing private/main:
$(sed 's/^/    /' <<<"${conflicts}")
    Resolve by hand per the runbook and push to ${PUBLIC_REPO} yourself.
    The release itself already completed; only the public mirror is pending."
fi

if git diff --cached --quiet; then
  note "Squash produced no staged changes — nothing to commit."
  exit 0
fi

git commit --quiet -m "Sync from ${PRIVATE_REPO} for release ${version}"

if [ "${DRY_RUN:-false}" = "true" ]; then
  note "DRY_RUN: would push to ${PUBLIC_REPO} main"
  git push --dry-run origin main
else
  note "Pushing to ${PUBLIC_REPO} main"
  git push origin main
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Public mirror"
    echo
    echo "Squashed \`${PRIVATE_REPO}@main\` onto [\`${PUBLIC_REPO}\`](https://github.com/${PUBLIC_REPO}) for release ${version}."
    if [ "${DRY_RUN:-false}" = "true" ]; then
      echo
      echo "_Dry run — nothing was pushed._"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi
