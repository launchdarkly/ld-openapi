#!/usr/bin/env bash
#
# Runbook step 11: mirror this private repo onto the public launchdarkly/ld-openapi.
#
# Usage: mirror-public.sh VERSION
#
# Env:
#   PUBLIC_TOKEN   push and pull-request rights on launchdarkly/ld-openapi,
#                  including workflows: the ld-openapi-mirror OctoSTS token
#                  .github/workflows/mirror-public.yml mints (required)
#   PRIVATE_TOKEN  read on this repo; GITHUB_TOKEN will do (required)
#   DRY_RUN        true = build the sync commit, push and open nothing
#
# Not the releaser PAT: GitHub refuses a PAT's push of workflow files without
# the workflow scope, and the sync usually changes .github/workflows.
#
# The public repo gets private main's tree as one commit on top of its own main.
# Not `git merge --squash`: a squash never records private's history as merged,
# so every sync merged from the same old base and conflicted on any file that
# changed again since the last sync, which was most release runs.
#
# The commit goes to branch mirror/sync as a pull request, not straight to main:
# the public main requires a pull request, and this makes this repo's content
# public, which is not practically reversible, so a person merges it. A newer
# sync replaces an unmerged one, the way release/next works.
#
# Copying the tree overwrites the public repo, so it only does so when nothing
# would be lost: the public tree has to be one private main once had, which is
# the case when every change to the public repo came from these pull requests.
# If someone changed the public repo directly, this aborts and leaves the
# release otherwise complete, because publishing over that is a human decision
# (the runbook: "generally I'd choose the private repo one, but use your
# discretion").

set -euo pipefail

version=${1:?usage: mirror-public.sh VERSION}
: "${PUBLIC_TOKEN:?PUBLIC_TOKEN is required}"
: "${PRIVATE_TOKEN:?PRIVATE_TOKEN is required}"

PUBLIC_REPO=launchdarkly/ld-openapi
PRIVATE_REPO=launchdarkly/ld-openapi-private
BRANCH=mirror/sync

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

note() { echo "==> $*"; }
fail() { echo "MIRROR FAILED: $*" >&2; exit 1; }
gh_public() { GH_TOKEN="${PUBLIC_TOKEN}" gh "$@" --repo "${PUBLIC_REPO}"; }

note "Cloning ${PUBLIC_REPO}"
git clone --quiet "https://x-access-token:${PUBLIC_TOKEN}@github.com/${PUBLIC_REPO}.git" "${workdir}/public"
cd "${workdir}/public"

git config user.name LaunchDarklyReleaseBot
git config user.email launchdarklyreleasebot@launchdarkly.com

git remote add private "https://x-access-token:${PRIVATE_TOKEN}@github.com/${PRIVATE_REPO}.git"
git fetch --quiet private main
private_sha=$(git rev-parse private/main)

open_pr=""
if [ "${DRY_RUN:-false}" != "true" ]; then
  open_pr=$(gh_public pr list --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')
fi

if git diff --quiet HEAD private/main; then
  note "Public repo already matches private main — nothing to mirror."
  if [ -n "${open_pr}" ]; then
    gh_public pr close "${open_pr}" --delete-branch \
      --comment "${PUBLIC_REPO} already matches ${PRIVATE_REPO}@${private_sha:0:10}, so this sync is no longer needed."
  fi
  exit 0
fi

# Find the private commit the public repo was last synced from: one whose tree
# is exactly the public tree. awk reads to the end: exiting early would SIGPIPE
# git log, which pipefail and set -e turn into a silent exit.
public_tree=$(git rev-parse 'HEAD^{tree}')
synced_from=$(git log --format='%H %T' private/main | awk -v t="${public_tree}" '$2 == t && !found { print $1; found = 1 }')
if [ -z "${synced_from}" ]; then
  fail "${PUBLIC_REPO} has changes that did not come from ${PRIVATE_REPO}: its tree matches no commit on private main.
    Recent ${PUBLIC_REPO} commits:
$(git log --format='      %h %an: %s' -5 HEAD)
    Bring those changes into ${PRIVATE_REPO} (or decide to drop them), then
    sync by hand or re-run this job. The release itself already completed;
    only the public mirror is pending."
fi
note "${PUBLIC_REPO} matches ${PRIVATE_REPO}@${synced_from:0:10}; copying ${private_sha:0:10}"

note "Files that will change on ${PUBLIC_REPO}"
git diff --name-status HEAD private/main | sed 's/^/    /' | tee "${workdir}/files.txt"

# Index and working tree become private main's, including deletions.
git checkout --quiet -B "${BRANCH}"
git read-tree -u --reset private/main
git commit --quiet -m "Sync from ${PRIVATE_REPO} for release ${version}" \
  -m "${PRIVATE_REPO}@${private_sha}"

title="Sync from ${PRIVATE_REPO} for release ${version}"
{
  echo "Copies \`${PRIVATE_REPO}@${private_sha:0:10}\` onto this repository for API client release ${version}: one commit whose tree is exactly the private repository's \`main\`."
  echo
  echo "This makes that content public. Merge it once it has been reviewed; a later release replaces this pull request if it is still open. Merging with any method keeps the tree, which is what the next sync checks. Do not add commits here: change \`${PRIVATE_REPO}\` instead."
  echo
  echo "<details><summary>Files that change ($(grep -c . "${workdir}/files.txt"))</summary>"
  echo
  echo '```'
  head -n 200 "${workdir}/files.txt"
  echo '```'
  echo "</details>"
} > "${workdir}/body.md"

if [ "${DRY_RUN:-false}" = "true" ]; then
  note "DRY_RUN: would push ${BRANCH} and open or update its pull request"
  git push --dry-run --force origin "HEAD:refs/heads/${BRANCH}"
  pr_url=""
else
  git push --quiet --force origin "HEAD:refs/heads/${BRANCH}"
  if [ -n "${open_pr}" ]; then
    gh_public pr edit "${open_pr}" --title "${title}" --body-file "${workdir}/body.md"
    pr_url=$(gh_public pr view "${open_pr}" --json url --jq .url)
  else
    pr_url=$(gh_public pr create --base main --head "${BRANCH}" --title "${title}" --body-file "${workdir}/body.md")
  fi
  note "Mirror pull request: ${pr_url}"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Public mirror"
    echo
    if [ -n "${pr_url}" ]; then
      echo "Opened or updated ${pr_url} to copy \`${PRIVATE_REPO}@${private_sha:0:10}\` onto [\`${PUBLIC_REPO}\`](https://github.com/${PUBLIC_REPO}) for release ${version}. It needs a review and a merge."
    else
      echo "Built the sync of \`${PRIVATE_REPO}@${private_sha:0:10}\` for release ${version}."
      echo
      echo "_Dry run — nothing was pushed._"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi
