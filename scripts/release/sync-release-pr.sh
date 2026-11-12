#!/usr/bin/env bash
#
# Keeps one open release PR (branch release/next) in step with the spec
# production serves. Merging that PR is what releases the clients.
#
# The PR carries:
#   release-manifest.json  the version it will release, and the gonfalon commit
#                          and blob SHA of the spec it will release
#   CHANGELOG.md           a new section with the release notes
#
# The spec itself is not committed here. gonfalon commits the published spec and
# production serves it byte for byte, so a gonfalon commit pins it exactly: the
# release fetches it from there, and the previous release's commit is the
# baseline this script diffs against.
#
# The version is derived from the spec, not from changelog headings:
#   major  oasdiff finds a breaking change, or a name generated clients use
#          (schema, operationId, tag) was removed or renamed
#   minor  oasdiff finds any other API change, or a name was added
#   patch  descriptions and examples only
# A release:major / release:minor / release:patch label on the PR overrides it.
#
# Env:
#   GH_TOKEN        push and PR rights on this repo. Must not be GITHUB_TOKEN:
#                   pushes made with it start no workflows, so CI would never
#                   run on the release PR.
#   GONFALON_TOKEN  read on launchdarkly/gonfalon
#   OASDIFF         oasdiff binary (default: oasdiff on PATH)
#   IGNORE_BETA     true = changes to operations tagged "(beta)" alone never
#                   force a major (default false)
#   BASE            branch the PR targets (default main)
#   DRY_RUN         true = build the branch and PR body locally, push nothing

set -euo pipefail

GONFALON=launchdarkly/gonfalon
SPEC_PATH=apidocs/openapi-public-final.json
CHANGELOG_PATH=apidocs/CHANGELOG.md
SPEC_URL=https://app.launchdarkly.com/api/v2/openapi.json
GO_CLIENT_REPO=launchdarkly/api-client-go
BRANCH=release/next
BASE=${BASE:-main}
REPO=${GITHUB_REPOSITORY:-launchdarkly/ld-openapi-private}
OASDIFF=${OASDIFF:-oasdiff}
here=$(cd "$(dirname "$0")" && pwd)

fail() { echo "sync-release-pr FAILED: $*" >&2; exit 1; }
note() { echo "==> $*"; }
gh_gonfalon() { GH_TOKEN="${GONFALON_TOKEN}" gh "$@"; }

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

git fetch -q origin "${BASE}"
branch_exists=false
if git fetch -q origin "${BRANCH}" 2>/dev/null; then branch_exists=true; fi

# --- What production serves ----------------------------------------------------
note "Downloading ${SPEC_URL}"
curl -s -L --fail "${SPEC_URL}" -o "${workdir}/prod.json" || \
  fail "could not download ${SPEC_URL} (this endpoint fails intermittently; the next run retries)"
prod_blob=$(git hash-object "${workdir}/prod.json")

open_pr=$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')

git show "origin/${BASE}:release-manifest.json" > "${workdir}/manifest.json"
prev_version=$(jq -r .version "${workdir}/manifest.json")
prev_gonfalon_sha=$(jq -r '.gonfalonSha // empty' "${workdir}/manifest.json")
prev_blob=$(jq -r '.specBlob // empty' "${workdir}/manifest.json")
if [ -z "${prev_gonfalon_sha}" ] || [ -z "${prev_blob}" ]; then
  fail "release-manifest.json on ${BASE} needs gonfalonSha and specBlob for the last release"
fi

# A release dispatched without a release PR does not update release-manifest.json.
# Diffing against the release before it would offer to ship that release again,
# so stop until the manifest names the latest one. The tags are read anonymously,
# from outside this checkout: the client repo is public, and GH_TOKEN (like the
# auth header checkout configured) only reaches this repo.
(cd "${workdir}" && git ls-remote --tags --refs "https://github.com/${GO_CLIENT_REPO}.git" 'v*') \
  > "${workdir}/go-tags.txt" || fail "could not list ${GO_CLIENT_REPO} tags"
latest_tag=$(sed 's|.*refs/tags/v||' "${workdir}/go-tags.txt" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)
if [ -n "${latest_tag}" ] && [ "$(printf '%s\n' "${prev_version}" "${latest_tag}" | sort -V | tail -n 1)" != "${prev_version}" ]; then
  fail "${GO_CLIENT_REPO} has v${latest_tag}, newer than ${prev_version} in release-manifest.json on ${BASE}. A release shipped without a release PR: set release-manifest.json to its version, gonfalonSha and specBlob (that run's Preflight summary lists them)."
fi

if [ "${prev_blob}" = "${prod_blob}" ]; then
  note "Production serves the spec ${BASE} last released; nothing to release."
  if [ -n "${open_pr}" ] && [ "${DRY_RUN:-false}" != "true" ]; then
    gh pr close "${open_pr}" --repo "${REPO}" --comment "Production serves the released spec again, so there is nothing to release." --delete-branch
  fi
  exit 0
fi

# --- Which gonfalon commit that is -------------------------------------------
# gonfalon commits the published spec and production serves it byte for byte,
# so the blob SHA names the commit. Searching history instead of requiring
# gonfalon main to match means a busy main never blocks the PR.
note "Finding the ${GONFALON} commit production serves"
gonfalon_sha=""
for c in $(gh_gonfalon api "repos/${GONFALON}/commits?path=${SPEC_PATH}&per_page=30" --jq '.[].sha'); do
  b=$(gh_gonfalon api "repos/${GONFALON}/git/trees/${c}:$(dirname "${SPEC_PATH}")" \
    --jq ".tree[] | select(.path == \"$(basename "${SPEC_PATH}")\") | .sha")
  if [ "${b}" = "${prod_blob}" ]; then gonfalon_sha=${c}; break; fi
done
[ -n "${gonfalon_sha}" ] || fail "production's spec (blob ${prod_blob}) matches none of the last 30 commits to ${SPEC_PATH}"
echo "    ${gonfalon_sha}"

# --- Version -----------------------------------------------------------------
# The baseline is gonfalon's own file at the last release's commit. Not the
# api/openapi.yaml bundled in api-client-go: openapi-generator rewrites the spec
# (it extracts inline request bodies into new schemas), so diffing against it
# reports names as removed that were never in gonfalon's spec.
gh_gonfalon api "repos/${GONFALON}/contents/${SPEC_PATH}?ref=${prev_gonfalon_sha}" \
  -H "Accept: application/vnd.github.raw" > "${workdir}/base.json"
[ "$(git hash-object "${workdir}/base.json")" = "${prev_blob}" ] || \
  fail "${SPEC_PATH} at ${GONFALON}@${prev_gonfalon_sha} is not blob ${prev_blob} from release-manifest.json"

base=${workdir}/base.json
rev=${workdir}/prod.json
surface_flags=()
if [ "${IGNORE_BETA:-false}" = "true" ]; then
  # Drop operations whose tags are all "(beta)" before oasdiff sees them.
  # shellcheck disable=SC2016 # a jq program, not shell
  drop_beta='.paths |= map_values(with_entries(select(
    (.value | type) != "object" or ((.value.tags // []) as $t
      | ($t | length) == 0 or ([$t[] | endswith("(beta)")] | all | not)))))'
  jq "${drop_beta}" "${base}" > "${workdir}/base-nobeta.json"
  jq "${drop_beta}" "${rev}" > "${workdir}/rev-nobeta.json"
  base=${workdir}/base-nobeta.json
  rev=${workdir}/rev-nobeta.json
  surface_flags+=(--ignore-beta)
fi

"${OASDIFF}" breaking "${base}" "${rev}" -f singleline > "${workdir}/breaking.txt"
"${OASDIFF}" changelog "${base}" "${rev}" -f singleline > "${workdir}/changelog.txt"
python3 -I "${here}/client-surface.py" "${workdir}/base.json" "${workdir}/prod.json" "${surface_flags[@]}" > "${workdir}/surface.json"

breaking=$(grep -c '^error' "${workdir}/breaking.txt" || true)
api_changes=$(grep -cE '^(error|warning|info)' "${workdir}/changelog.txt" || true)
names_removed=$(jq '[.removed[] | length] | add' "${workdir}/surface.json")
names_added=$(jq '[.added[] | length] | add' "${workdir}/surface.json")

if [ "${breaking}" -gt 0 ] || [ "${names_removed}" -gt 0 ]; then
  bump="major"
elif [ "${api_changes}" -gt 0 ] || [ "${names_added}" -gt 0 ]; then
  bump="minor"
else
  bump="patch"
fi
derived=${bump}
if [ -n "${open_pr}" ]; then
  label=$(gh pr view "${open_pr}" --repo "${REPO}" --json labels \
    --jq '[.labels[].name | select(test("^release:(major|minor|patch)$"))] | .[0] // empty')
  [ -z "${label}" ] || bump=${label#release:}
fi

IFS=. read -r prev_major prev_minor prev_patch <<<"${prev_version}"
case "${bump}" in
  major) version="$(( prev_major + 1 )).0.0" ;;
  minor) version="${prev_major}.$(( prev_minor + 1 )).0" ;;
  patch) version="${prev_major}.${prev_minor}.$(( prev_patch + 1 ))" ;;
esac
note "Version ${version} (${bump}; derived ${derived}: ${breaking} breaking, ${names_removed} names removed, ${names_added} added, ${api_changes} API changes)"

# --- Notes ---------------------------------------------------------------------
gh_gonfalon api "repos/${GONFALON}/contents/${CHANGELOG_PATH}?ref=${gonfalon_sha}" \
  -H "Accept: application/vnd.github.raw" > "${workdir}/gonfalon-changelog.md"
notes_args=("${workdir}/gonfalon-changelog.md")
gh_gonfalon api "repos/${GONFALON}/contents/${CHANGELOG_PATH}?ref=${prev_gonfalon_sha}" \
  -H "Accept: application/vnd.github.raw" > "${workdir}/gonfalon-changelog-prev.md"
notes_args+=("${workdir}/gonfalon-changelog-prev.md")
python3 -I "${here}/release-notes.py" "${notes_args[@]}" > "${workdir}/notes.md"
grep -q '[^[:space:]]' "${workdir}/notes.md" || \
  echo "_No gonfalon changelog entries. See the API changes in the release PR._" > "${workdir}/notes.md"

# --- The branch ----------------------------------------------------------------
git checkout -q -B "${BRANCH}" "origin/${BASE}"
jq -n --arg v "${version}" --arg p "${prev_version}" --arg b "${bump}" --arg g "${gonfalon_sha}" --arg s "${prod_blob}" \
  '{version: $v, previousVersion: $p, bump: $b, gonfalonSha: $g, specBlob: $s}' > release-manifest.json
python3 -I - "${version}" "${workdir}/notes.md" <<'PY'
import datetime, os, sys
version, notes_path = sys.argv[1], sys.argv[2]
path = "CHANGELOG.md"
text = open(path).read() if os.path.exists(path) else "# Changelog\n\nAll notable changes to the LaunchDarkly REST API clients.\n"
head, sep, rest = text.partition("\n## [")
entry = f"## [{version}] - {datetime.date.today().isoformat()}\n\n{open(notes_path).read().strip()}\n"
open(path, "w").write(head.rstrip("\n") + "\n\n" + entry + (sep + rest if sep else ""))
PY
git add release-manifest.json CHANGELOG.md
git -c user.name="LaunchDarklyReleaseBot" -c user.email="launchdarklyreleasebot@launchdarkly.com" \
  commit -q -m "chore: release ${version}" -m "Spec from ${GONFALON}@${gonfalon_sha}."

# --- The PR body ---------------------------------------------------------------
details() { # title, file, max lines, [count to show]
  local n; n=$(grep -c . "$2" || true)
  [ "${n}" -gt 0 ] || return 0
  echo "<details><summary>$1 (${4:-${n}})</summary>"; echo; echo '```'
  head -n "$3" "$2"; [ "${n}" -le "$3" ] || echo "… $(( n - $3 )) more in the Release PR run's summary"
  echo '```'; echo "</details>"; echo
}
jq -r '.removed | to_entries[] | select(.value | length > 0) | "\(.key): \(.value | join(", "))"' "${workdir}/surface.json" > "${workdir}/removed.txt"
jq -r '.added | to_entries[] | select(.value | length > 0) | "\(.key): \(.value | join(", "))"' "${workdir}/surface.json" > "${workdir}/added.txt"
# Drop oasdiff's "at /tmp/…/prod.json," location: it names a temporary file.
tidy_oasdiff() { grep -E '^(error|warning|info)' "$1" | sed -E 's/^(error|warning|info) at [^,]*, in /\1: /' || true; }
tidy_oasdiff "${workdir}/breaking.txt" | grep -E '^(error|warning)' > "${workdir}/breaking-lines.txt" || true
tidy_oasdiff "${workdir}/changelog.txt" > "${workdir}/changelog-lines.txt"
{
  echo "Merging this PR releases the API clients as **${version}**."
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Spec | [${GONFALON}@\`${gonfalon_sha:0:10}\`](https://github.com/${GONFALON}/commit/${gonfalon_sha}), what production serves |"
  echo "| Previous release | \`${prev_version}\` |"
  if [ "${bump}" = "${derived}" ]; then
    echo "| Bump | **${bump}** |"
  else
    echo "| Bump | **${bump}** (label; the spec says ${derived}) |"
  fi
  echo "| oasdiff | ${breaking} breaking, ${api_changes} changes in total |"
  echo "| Client names | ${names_removed} removed or renamed, ${names_added} added |"
  echo
  echo "Add a \`release:major\`, \`release:minor\` or \`release:patch\` label to override the bump; it applies on the next sync. Fix the notes in gonfalon's \`${CHANGELOG_PATH}\`, not here: this branch is regenerated."
  echo
  # Changes first: if the body has to be cut, the full notes are still in CHANGELOG.md.
  echo "## API changes"
  echo
  details "Client names removed or renamed" "${workdir}/removed.txt" 100 "${names_removed}"
  details "Client names added" "${workdir}/added.txt" 100 "${names_added}"
  details "oasdiff breaking changes" "${workdir}/breaking-lines.txt" 60
  details "oasdiff changelog" "${workdir}/changelog-lines.txt" 60
  echo "## Release notes"
  echo
  cat "${workdir}/notes.md"
} > "${workdir}/body.md"
# GitHub rejects bodies over 65536 characters.
if [ "$(wc -c < "${workdir}/body.md")" -gt 65000 ]; then
  head -c 64000 "${workdir}/body.md" > "${workdir}/body.trunc"
  printf '\n\n_Truncated. The full notes are in CHANGELOG.md on this branch._\n' >> "${workdir}/body.trunc"
  mv "${workdir}/body.trunc" "${workdir}/body.md"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    cat "${workdir}/body.md"
    echo; echo "## Full oasdiff output"; echo; echo '```'
    cat "${workdir}/breaking-lines.txt" "${workdir}/changelog-lines.txt"
    echo '```'
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [ "${DRY_RUN:-false}" = "true" ]; then
  cp "${workdir}/body.md" ./release-pr-body.md
  note "Dry run: branch ${BRANCH} built locally, PR body in release-pr-body.md; nothing pushed."
  exit 0
fi

# --- Push and open or update the PR ----------------------------------------------
# Lines that differ from what release/next holds, leaving out the CHANGELOG
# heading's date: it is today's, so without this the branch would change every
# day the PR stays open, re-running CI and dismissing approvals each time. The
# date catches up with the next real change.
# shellcheck disable=SC2001 # ${v//./\\.} escapes differently in bash 3.2 and 5
version_re=$(sed 's/\./\\./g' <<<"${version}")
changed_lines() {
  git diff -U0 "origin/${BRANCH}" HEAD -- "$@" | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' |
    grep -vE "^[-+]## \[${version_re}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" || true
}
# Merging is the release, so an approval must not carry over to a different
# release, and main's rules do not dismiss approvals on push. Each approval is
# checked against the manifest at the commit it approved, so a dismissal that
# failed is retried by the next sync rather than lost: the release files are
# what an approval covers, and a push that only picks up main keeps them.
# Runs before the push, so a stale approval never sits on a new release; if a
# dismissal fails, the sync stops with the branch unchanged.
if [ -n "${open_pr}" ]; then
  current_manifest=$(jq -S . release-manifest.json)
  gh api --paginate "repos/${REPO}/pulls/${open_pr}/reviews" \
    --jq '.[] | select(.state == "APPROVED") | "\(.id) \(.commit_id)"' > "${workdir}/approvals.txt"
  while read -r review commit; do
    approved_manifest=$(gh api "repos/${REPO}/contents/release-manifest.json?ref=${commit}" \
      -H "Accept: application/vnd.github.raw" 2>/dev/null | jq -S . 2>/dev/null || true)
    if [ "${approved_manifest}" = "${current_manifest}" ]; then
      continue
    fi
    note "Dismissing approval ${review}: it approved a different release (at ${commit:0:10})"
    gh api -X PUT "repos/${REPO}/pulls/${open_pr}/reviews/${review}/dismissals" \
      -f message="This release PR now releases ${version} from ${GONFALON}@${gonfalon_sha:0:10}. Review it again." \
      -f event=DISMISS >/dev/null
  done < "${workdir}/approvals.txt"
fi

# Only push when something changed, so an unchanged spec does not re-run CI.
# (CI downloads the spec from production, so a push is also what makes the PR's
# checks run against a newly deployed spec.)
if [ "${branch_exists}" = "true" ] && [ -z "$(changed_lines .)" ]; then
  note "${BRANCH} is already up to date"
else
  git push -q --force origin "HEAD:refs/heads/${BRANCH}"
fi
if [ -n "${open_pr}" ]; then
  gh pr edit "${open_pr}" --repo "${REPO}" --title "chore: release ${version}" --body-file "${workdir}/body.md"
else
  gh pr create --repo "${REPO}" --base "${BASE}" --head "${BRANCH}" --title "chore: release ${version}" --body-file "${workdir}/body.md"
fi
