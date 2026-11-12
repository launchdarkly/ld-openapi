#!/usr/bin/env bash
#
# Derives every input the release needs and enforces the preflight gates from the
# release runbook.
#
# Requires: gh, curl, git.
#
# Two GitHub tokens, because they answer to different repos:
#   GH_TOKEN         the releaser token (BOT_TOKEN) — client repos only, used for
#                    the tag-collision check and, with FORCE, tag deletes.
#   GONFALON_TOKEN   read on launchdarkly/gonfalon, for the spec-parity gate, the
#                    CI gate, and the changelog. In CI this is an OctoSTS token
#                    minted at runtime from the ld-openapi-downstream trust policy.
#                    The releaser token deliberately has no gonfalon access and
#                    should not be granted any just to read a file.
#
# Env:
#   VERSION_OVERRIDE     skip version derivation and use this bare semver
#   BUMP_OVERRIDE        major|minor|patch — skip changelog inference
#   FORCE                true = delete colliding tags instead of aborting
#   PARITY_TIMEOUT       seconds to wait for prod to catch up to gonfalon main (default 1800)
#   PARITY_INTERVAL      seconds between parity polls (default 60)
#   SKIP_CI_GATE         true = don't require gonfalon main to be green
#   SKIP_SPEC_PARITY     true = release what prod serves even if main is ahead
#   RELEASE_MANIFEST     path to release-manifest.json: release what a merged
#                        release PR recorded. Version, gonfalon commit and notes
#                        come from the PR instead of being derived, and Gate 1
#                        fetches the spec from that gonfalon commit and checks its
#                        blob SHA. VERSION_OVERRIDE, BUMP_OVERRIDE and the parity
#                        settings are ignored; FORCE and SKIP_CI_GATE still apply.
#   RELEASE_COMMIT       with RELEASE_MANIFEST: the pushed commit. Preflight fails
#                        unless it merged a release/next PR approved at its last
#                        commit. Unset on a dispatch, where the dispatcher decides.
#   REPO_TOKEN           read on this repo's pull requests, for RELEASE_COMMIT
#   DRY_RUN              true = a rehearsal; only changes what the summary says
#   SPEC_OUT             write the spec Gate 1 verified here, so the build ships
#                        those bytes rather than downloading production's again
#
# Writes version/bump/changelog to $GITHUB_OUTPUT when running under Actions,
# and always prints a human-readable summary.

set -euo pipefail

GONFALON=launchdarkly/gonfalon
SPEC_PATH=apidocs/openapi-public-final.json
CHANGELOG_PATH=apidocs/CHANGELOG.md
SPEC_URL=https://app.launchdarkly.com/api/v2/openapi.json
GO_CLIENT_REPO=launchdarkly/api-client-go

# Canonical repo names. `make push` clones api-client-typescript-axios, which is a
# GitHub redirect to api-client-typescript; use the canonical name for API calls.
CLIENT_REPOS=(
  launchdarkly/api-client-go
  launchdarkly/api-client-java
  launchdarkly/api-client-python
  launchdarkly/api-client-ruby
  launchdarkly/api-client-typescript
)

PARITY_TIMEOUT=${PARITY_TIMEOUT:-1800}
PARITY_INTERVAL=${PARITY_INTERVAL:-60}
workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

fail() { echo "PREFLIGHT FAILED: $*" >&2; exit 1; }
note() { echo "==> $*"; }

# Every gonfalon read goes through this, so the releaser token is never used
# against a repo it has no business reading.
GONFALON_TOKEN=${GONFALON_TOKEN:-}
[ -n "${GONFALON_TOKEN}" ] || \
  fail "GONFALON_TOKEN must be set — it is what reads ${GONFALON}. In CI it comes from the octosts-action step; locally, pass a token with read access. BOT_TOKEN has no access there."
gh_gonfalon() { GH_TOKEN="${GONFALON_TOKEN}" gh "$@"; }

if [ -n "${RELEASE_MANIFEST:-}" ]; then
  # --- Release PR mode: the merged PR already settled what to release ----------
  version=$(jq -r .version "${RELEASE_MANIFEST}")
  prev_version=$(jq -r .previousVersion "${RELEASE_MANIFEST}")
  bump=$(jq -r .bump "${RELEASE_MANIFEST}")
  gonfalon_sha=$(jq -r .gonfalonSha "${RELEASE_MANIFEST}")
  spec_blob=$(jq -r .specBlob "${RELEASE_MANIFEST}")
  grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"${version}" || fail "${RELEASE_MANIFEST} has no valid version (got '${version}')"
  if [ "${gonfalon_sha}" = "null" ] || [ "${spec_blob}" = "null" ]; then
    fail "${RELEASE_MANIFEST} needs gonfalonSha and specBlob"
  fi
  note "Release PR mode: ${version} (${bump} from ${prev_version}), spec from ${GONFALON}@${gonfalon_sha:0:9}"

  # On a push, the merge is the go-ahead, so check it was one: a release/next PR
  # with an approval of this release. main's rules keep an approval through a
  # push, and the bot can force-push a new spec between an approval and the merge.
  # An approval counts when release-manifest.json at the commit it approved is
  # the one that merged: the same rule sync-release-pr.sh uses to keep or
  # dismiss approvals, so a push that only picked up main (which keeps them)
  # does not block the release.
  if [ -n "${RELEASE_COMMIT:-}" ]; then
    note "Checking that ${RELEASE_COMMIT:0:9} merged an approved release PR"
    repo=${GITHUB_REPOSITORY:-launchdarkly/ld-openapi-private}
    pr=$(GH_TOKEN="${REPO_TOKEN:?REPO_TOKEN must be set to check the release PR}" gh api \
      "repos/${repo}/commits/${RELEASE_COMMIT}/pulls" \
      --jq '[.[] | select(.merged_at != null and .head.ref == "release/next")][0] // empty | "\(.number) \(.head.sha)"')
    [ -n "${pr}" ] || fail "${RELEASE_COMMIT} changed ${RELEASE_MANIFEST} without merging a release/next PR, so nothing was released. If it should release, dispatch release.yml with fromManifest."
    read -r pr_number pr_head <<<"${pr}"
    merged_manifest=$(jq -S . "${RELEASE_MANIFEST}")
    approvals=""
    while read -r login commit; do
      [ -n "${commit}" ] || continue
      approved_manifest=$(GH_TOKEN="${REPO_TOKEN}" gh api "repos/${repo}/contents/release-manifest.json?ref=${commit}" \
        -H "Accept: application/vnd.github.raw" 2>/dev/null | jq -S . 2>/dev/null || true)
      if [ "${approved_manifest}" = "${merged_manifest}" ]; then
        approvals+="${login}@${commit:0:9}"$'\n'
      fi
    done < <(GH_TOKEN="${REPO_TOKEN}" gh api --paginate "repos/${repo}/pulls/${pr_number}/reviews" \
      --jq '.[] | select(.state == "APPROVED") | "\(.user.login) \(.commit_id)"')
    [ -n "${approvals}" ] || fail "release PR #${pr_number} merged without an approval of the release it merged (${version} from ${GONFALON}@${gonfalon_sha:0:9}). Review what it releases, then dispatch release.yml with fromManifest."
    echo "    #${pr_number} (head ${pr_head:0:9}), approved by $(grep . <<<"${approvals}" | sort -u | paste -sd, -)"
  fi

  # The spec is not committed here; the gonfalon commit pins it. The blob check
  # catches a truncated download as well as a manifest edited by hand.
  note "Gate 1: fetching ${SPEC_PATH} at ${GONFALON}@${gonfalon_sha:0:9}"
  gh_gonfalon api "repos/${GONFALON}/contents/${SPEC_PATH}?ref=${gonfalon_sha}" \
    -H "Accept: application/vnd.github.raw" > "${workdir}/prod-openapi.json" || \
    fail "could not read ${SPEC_PATH} at ${GONFALON}@${gonfalon_sha}"
  prod_blob=$(git hash-object "${workdir}/prod-openapi.json")
  [ "${prod_blob}" = "${spec_blob}" ] || \
    fail "${SPEC_PATH} at ${GONFALON}@${gonfalon_sha} is blob ${prod_blob}, but ${RELEASE_MANIFEST} says ${spec_blob}"
  echo "    matches (blob ${prod_blob})"

  awk -v h="## [${version}]" '
    index($0, h) == 1 { capture = 1; next }
    /^## \[/          { capture = 0 }
    capture           { print }
  ' CHANGELOG.md > "${workdir}/unreleased.md"
  sed -i'' -e '/./,$!d' "${workdir}/unreleased.md"
  grep -q '[^[:space:]]' "${workdir}/unreleased.md" || fail "CHANGELOG.md has no notes under ## [${version}]"
  major=${version%%.*}
else

# --- Gate 1: prod serves exactly what gonfalon main has committed -------------
# This replaces both the Slack "nothing mid-flight" check and the "wait for the
# commit to be deployed to production" wait. gonfalon commits the published spec,
# and prod serves that file byte for byte, so a git blob SHA comparison settles it:
# equal   -> prod is caught up AND nothing is mid-flight; safe to release.
# unequal -> either a merged spec change isn't deployed yet, or one just landed.
#
# Compared via `git hash-object` rather than downloading gonfalon's copy: the file
# is ~2.8MB, over the contents API's 1MB raw limit, but the tree API always
# returns its blob SHA.
#
# main is re-resolved on every poll so we converge on wherever main currently is,
# then frozen: every later read (CI status, changelog) uses that one commit. Doing
# otherwise lets a merge land mid-preflight and pair a changelog with a spec it
# does not describe — gonfalon's main moves often enough for that to be real.
note "Gate 1: comparing prod spec against ${GONFALON} main:${SPEC_PATH}"
spec_dir=$(dirname "${SPEC_PATH}")
spec_file=$(basename "${SPEC_PATH}")
deadline=$(( $(date +%s) + PARITY_TIMEOUT ))
while :; do
  gonfalon_sha=$(gh_gonfalon api "repos/${GONFALON}/commits/main" --jq '.sha')
  [ -n "${gonfalon_sha}" ] || fail "could not resolve ${GONFALON} main"

  curl -s -L --fail "${SPEC_URL}" -o "${workdir}/prod-openapi.json" || \
    fail "could not download ${SPEC_URL} (this endpoint fails intermittently — retry the run)"

  prod_blob=$(git hash-object "${workdir}/prod-openapi.json")
  main_blob=$(gh_gonfalon api "repos/${GONFALON}/git/trees/${gonfalon_sha}:${spec_dir}" \
    --jq ".tree[] | select(.path == \"${spec_file}\") | .sha")

  [ -n "${main_blob}" ] || fail "could not read blob SHA for ${SPEC_PATH} at ${GONFALON}@${gonfalon_sha}"

  if [ "${prod_blob}" = "${main_blob}" ]; then
    echo "    in sync at ${gonfalon_sha:0:9} (blob ${prod_blob})"
    break
  fi

  # SKIP_SPEC_PARITY releases what production is serving even though main is ahead.
  # The build downloads the spec from prod either way, so this does not change what
  # ships — it changes whether we refuse to ship. What it costs: the changelog and
  # version still come from main, so the release notes may describe spec changes
  # that are merged but not yet deployed, and the downstream gonfalon PR would
  # record them against this version. Trim those entries from that PR before
  # merging it; it requires review anyway.
  if [ "${SKIP_SPEC_PARITY:-false}" = "true" ]; then
    echo "    NOT IN SYNC, but SKIP_SPEC_PARITY=true — proceeding."
    echo "    prod blob ${prod_blob}"
    echo "    main blob ${main_blob} at ${gonfalon_sha:0:9}"
    echo "    Releasing the spec production currently serves. Check the changelog"
    echo "    entries in the gonfalon PR against what actually shipped before merging it."
    break
  fi

  # Two blob hashes say nothing about what is being waited on. Resolve prod's blob
  # back to the gonfalon commit that produced it, once, on the first mismatch.
  if [ -z "${drift_explained:-}" ]; then
    drift_explained=1
    echo "    not in sync. Resolving which commit prod is serving..."
    spec_history=$(gh_gonfalon api \
      "repos/${GONFALON}/commits?path=${SPEC_PATH}&per_page=20" \
      --jq '.[] | "\(.sha) \(.commit.committer.date) \(.commit.message | split("\n")[0])"' 2>/dev/null || true)

    prod_commit=""
    while IFS= read -r line; do
      [ -n "${line}" ] || continue
      c=${line%% *}
      b=$(gh_gonfalon api "repos/${GONFALON}/git/trees/${c}:${spec_dir}" \
        --jq ".tree[] | select(.path == \"${spec_file}\") | .sha" 2>/dev/null || true)
      if [ "${b}" = "${prod_blob}" ]; then prod_commit=${line}; break; fi
    done <<<"${spec_history}"

    main_line=$(head -1 <<<"${spec_history}")
    if [ -n "${prod_commit}" ]; then
      echo "    prod is serving ${SPEC_PATH} from ${prod_commit}"
    else
      echo "    WARNING: prod's spec matches no recent commit on main. It may be serving"
      echo "             something unreleased, or the file moved. Investigate before releasing."
    fi
    echo "    main's latest spec commit is ${main_line}"
    echo "    Waiting for that to reach production."
  fi

  now=$(date +%s)
  if [ "${now}" -ge "${deadline}" ]; then
    fail "prod spec (${prod_blob}) still differs from ${GONFALON} main (${main_blob}) after ${PARITY_TIMEOUT}s.
    Waiting on: ${main_line:-the latest spec commit on main} to deploy to production.
    Releasing before it does would publish release notes describing a spec that
    production is not yet serving. Either wait for the deploy and re-dispatch, or
    raise PARITY_TIMEOUT. Check the gonfalon deploy pipeline and #proj-openapi."
  fi
  echo "    still waiting, retrying in ${PARITY_INTERVAL}s ($(( deadline - now ))s left)"
  sleep "${PARITY_INTERVAL}"
done

fi

# Hand the build the bytes Gate 1 checked: downloading production's spec again
# could pick up a deploy that landed after the check.
[ -z "${SPEC_OUT:-}" ] || cp "${workdir}/prod-openapi.json" "${SPEC_OUT}"

# --- Gate 2: that gonfalon commit is green ------------------------------------
# The runbook's "make sure CI is passing (basically: Gonfalon is currently in a
# good state)", pinned to the commit whose spec we are about to ship.
# Uses check-runs only. The combined-status endpoint
# (/commits/{sha}/status) needs the `statuses` permission, which no policy in
# launchdarkly/.github-private grants and which may not be available on the
# OctoSTS app at all; `checks: read` is granted and has precedent
# (service-template-go-sync). check-runs covers the GitHub Actions checks, which
# is what "is gonfalon green" means here. The tradeoff is that legacy commit
# statuses from external systems are not considered.
if [ "${SKIP_CI_GATE:-false}" != "true" ]; then
  note "Gate 2: checking CI for ${GONFALON}@${gonfalon_sha:0:9}"
  check_runs=$(gh_gonfalon api "repos/${GONFALON}/commits/${gonfalon_sha}/check-runs" --paginate) || \
    fail "could not read check runs for ${GONFALON}@${gonfalon_sha:0:9}.
    If this is HTTP 403, the federated token is missing 'checks: read' — add it to
    .github/launchdarkly/ld-openapi-downstream.sts.yaml in launchdarkly/.github-private."

  total=$(jq '[.check_runs[]] | length' <<<"${check_runs}")
  failed_checks=$(jq '[.check_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out")] | length' <<<"${check_runs}")

  if [ "${failed_checks}" -gt 0 ]; then
    jq -r '.check_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "  failed: \(.name)"' <<<"${check_runs}" >&2 || true
    fail "${GONFALON}@${gonfalon_sha:0:9} is not green (${failed_checks} of ${total} checks failed). Set SKIP_CI_GATE=true to override."
  fi
  echo "    green (${total} check runs, none failed)"
else
  echo "    Gate 2 skipped (SKIP_CI_GATE=true)"
fi

# The release PR settled notes, bump and version; the rest derives them.
if [ -z "${RELEASE_MANIFEST:-}" ]; then

# --- Changelog: extract the [Unreleased] body --------------------------------
note "Reading ${CHANGELOG_PATH} at ${GONFALON}@${gonfalon_sha:0:9}"
gh_gonfalon api "repos/${GONFALON}/contents/${CHANGELOG_PATH}?ref=${gonfalon_sha}" \
  -H "Accept: application/vnd.github.raw" > "${workdir}/CHANGELOG.md" || \
  fail "could not read ${CHANGELOG_PATH} from ${GONFALON}@${gonfalon_sha}"

awk '
  /^## \[Unreleased\]/ { capture = 1; next }
  /^## \[/            { capture = 0 }
  capture             { print }
' "${workdir}/CHANGELOG.md" > "${workdir}/unreleased.md"

# Trim leading/trailing blank lines.
sed -i'' -e '/./,$!d' "${workdir}/unreleased.md"
printf '%s\n' "$(cat "${workdir}/unreleased.md")" > "${workdir}/unreleased.md"

if ! grep -q '[^[:space:]]' "${workdir}/unreleased.md"; then
  fail "the [Unreleased] section of ${CHANGELOG_PATH} is empty — there is nothing to release"
fi

# --- Bump type: inferred from the [Unreleased] section headings ---------------
# Removed/Changed  -> major (both have historically carried breaking changes)
# Added/Deprecated -> minor
# Bug Fixes/Fixed  -> patch
#
# NOTE: `### Changed` is genuinely ambiguous — it covers breaking and additive
# changes alike — so this rule deliberately errs toward major. Override with
# BUMP_OVERRIDE when you know better.
headings=$(grep -E '^### ' "${workdir}/unreleased.md" | sed 's/^### //' | sort -u || true)
[ -n "${headings}" ] || fail "no '### ' headings found under [Unreleased]; cannot infer a bump type"

if [ -n "${BUMP_OVERRIDE:-}" ]; then
  bump=${BUMP_OVERRIDE}
  case "${bump}" in
    major|minor|patch) ;;
    *) fail "BUMP_OVERRIDE must be major, minor, or patch (got '${bump}')" ;;
  esac
  note "Bump type: ${bump} (overridden)"
elif grep -qxE 'Removed|Changed' <<<"${headings}"; then
  bump="major"
elif grep -qxE 'Added|Deprecated' <<<"${headings}"; then
  bump="minor"
elif grep -qxE 'Bug Fixes|Fixed|Security' <<<"${headings}"; then
  bump="patch"
else
  fail "unrecognised [Unreleased] headings, cannot infer a bump type:
$(sed 's/^/    /' <<<"${headings}")
    Add the heading to preflight.sh's rule or pass BUMP_OVERRIDE."
fi
[ -n "${BUMP_OVERRIDE:-}" ] || note "Bump type: ${bump} (from headings: $(paste -sd, - <<<"${headings}"))"

# --- Version: previous api-client-go tag + bump ------------------------------
# Sort explicitly rather than trusting the tags endpoint's order, which GitHub
# does not document as semver-descending — and lexicographic order would put
# v9.0.0 above v17.0.0 anyway.
prev_tag=$(gh api --paginate "repos/${GO_CLIENT_REPO}/tags" --jq '.[].name' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[ -n "${prev_tag}" ] || fail "could not read the latest tag from ${GO_CLIENT_REPO}"
prev_version=${prev_tag#v}

IFS=. read -r prev_major prev_minor prev_patch <<<"${prev_version}"
case "${bump}" in
  major) version="$(( prev_major + 1 )).0.0" ;;
  minor) version="${prev_major}.$(( prev_minor + 1 )).0" ;;
  patch) version="${prev_major}.${prev_minor}.$(( prev_patch + 1 ))" ;;
esac

if [ -n "${VERSION_OVERRIDE:-}" ]; then
  grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"${VERSION_OVERRIDE}" || \
    fail "VERSION_OVERRIDE must be bare semver MAJOR.MINOR.PATCH with no leading 'v' (got '${VERSION_OVERRIDE}')"
  note "Version: ${VERSION_OVERRIDE} (overridden; derivation said ${version})"
  version=${VERSION_OVERRIDE}
else
  note "Version: ${version} (previous ${prev_version}, ${bump} bump)"
fi
major=${version%%.*}

fi

# --- Gate 3: no colliding tags ----------------------------------------------
# A re-run after a partial failure trips over tags the previous attempt created.
# Non-Go repos get two tags per release: bare X.Y.Z from `make push`, and vX.Y.Z
# from the create-release job. Both have to go.
note "Gate 3: checking for existing ${version} / v${version} tags"
collisions=()
for repo in "${CLIENT_REPOS[@]}"; do
  for ref in "${version}" "v${version}"; do
    if gh api "repos/${repo}/git/ref/tags/${ref}" >/dev/null 2>&1; then
      collisions+=("${repo}#${ref}")
    fi
  done
done

if [ ${#collisions[@]} -gt 0 ]; then
  if [ "${FORCE:-false}" = "true" ]; then
    for collision in "${collisions[@]}"; do
      repo=${collision%%#*}
      ref=${collision##*#}
      echo "    deleting ${repo} tag ${ref}"
      gh api -X DELETE "repos/${repo}/git/refs/tags/${ref}"
    done
  else
    fail "tags for ${version} already exist:
$(printf '    %s\n' "${collisions[@]}")
    A previous release attempt got partway through. Delete these tags, or re-run with force=true."
  fi
fi

# --- Emit --------------------------------------------------------------------
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  delimiter="changelog-$(openssl rand -hex 8)"
  {
    echo "version=${version}"
    echo "major=${major}"
    echo "previous_version=${prev_version}"
    echo "bump=${bump}"
    echo "gonfalon_sha=${gonfalon_sha}"
    echo "changelog<<${delimiter}"
    cat "${workdir}/unreleased.md"
    echo "${delimiter}"
  } >> "${GITHUB_OUTPUT}"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Release ${version}"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Previous | \`${prev_version}\` |"
    echo "| Bump | ${bump} |"
    echo "| gonfalon commit | [\`${gonfalon_sha:0:9}\`](https://github.com/${GONFALON}/commit/${gonfalon_sha}) |"
    echo "| Spec blob | \`${prod_blob}\` |"
    echo
    if [ -z "${RELEASE_MANIFEST:-}" ] && [ "${DRY_RUN:-false}" != "true" ]; then
      # A dispatched release does not update release-manifest.json, and the next
      # release PR refuses to sync until main's names the latest release.
      echo "Not released from a release PR. Update \`release-manifest.json\` on main to this, or the release PR stops syncing:"
      echo
      echo '```json'
      jq -n --arg v "${version}" --arg g "${gonfalon_sha}" --arg s "${prod_blob}" \
        '{version: $v, gonfalonSha: $g, specBlob: $s}'
      echo '```'
      echo
    fi
    echo "<details><summary>Changelog</summary>"
    echo
    cat "${workdir}/unreleased.md"
    echo
    echo "</details>"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

note "Preflight passed. Releasing ${version}."
