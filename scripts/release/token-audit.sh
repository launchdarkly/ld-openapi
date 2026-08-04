#!/usr/bin/env bash
#
# Read-only audit of every credential the release needs. Makes no changes: only
# GETs and whoami-style calls, so it is safe to run any time.
#
# A dry run cannot answer "do the tokens have the right permissions?" on its own.
# It skips create-release entirely, pr-downstream skips PR creation, and the
# publish dry-run scripts never authenticate to any registry. This closes that
# gap by asking each provider directly.
#
# Exits non-zero if a required GitHub permission is missing or a verifiable
# registry credential is rejected. Credentials with no read-only verification
# path are reported as UNVERIFIED rather than silently passed.
#
# Secrets are read from the environment and never printed.

set -uo pipefail

# Set to false when the corresponding job is switched off for this run, so a
# missing credential cannot block a release that was never going to use it. This
# also lets the flow be rehearsed before those tokens exist.
REQUIRE_MIRROR_TOKEN=${REQUIRE_MIRROR_TOKEN:-true}
REQUIRE_DOWNSTREAM_TOKEN=${REQUIRE_DOWNSTREAM_TOKEN:-true}

pass=(); fail=(); unverified=(); skipped=()

ok()    { echo "  PASS       $1"; pass+=("$1"); }
bad()   { echo "  FAIL       $1"; fail+=("$1"); }
unver() { echo "  UNVERIFIED $1"; unverified+=("$1"); }
skip()  { echo "  SKIP       $1"; skipped+=("$1"); }

# --- GitHub tokens -----------------------------------------------------------
# `.permissions` on the repo endpoint reflects what THIS token can do, so it
# answers the push/read question without writing anything.
check_repo_perm() {
  local label=$1 token=$2 repo=$3 needed=$4

  if [ -z "${token}" ]; then
    bad "${label}: secret is not set (needs ${needed} on ${repo})"
    return
  fi

  # Terraform creates these SSM parameters holding a placeholder, so between the
  # first apply and someone writing the real value there is a window where the
  # secret exists but is the literal placeholder. Say so, rather than reporting
  # an opaque "Bad credentials".
  if [ "${token}" = "SET_IN_PARAMETER_STORE" ]; then
    bad "${label}: still holds the terraform placeholder. Write the real value to its SSM parameter, then re-apply terraform so the secret picks it up."
    return
  fi

  local body
  if ! body=$(GH_TOKEN="${token}" gh api "repos/${repo}" 2>&1); then
    if grep -qi "404\|not found" <<<"${body}"; then
      bad "${label}: cannot see ${repo} at all — token lacks access or repo is wrong (needs ${needed})"
    else
      bad "${label}: error reading ${repo} — $(head -1 <<<"${body}")"
    fi
    return
  fi

  local granted
  granted=$(jq -r '.permissions // {} | to_entries | map(select(.value)) | map(.key) | join(",")' <<<"${body}")

  if [ "${needed}" = "pull" ]; then
    # Any successful read satisfies a read requirement.
    ok "${label}: can read ${repo} (granted: ${granted:-read})"
  elif jq -e --arg p "${needed}" '.permissions[$p] == true' <<<"${body}" >/dev/null 2>&1; then
    ok "${label}: has ${needed} on ${repo} (granted: ${granted})"
  else
    bad "${label}: missing ${needed} on ${repo} (granted: ${granted:-none})"
  fi
}

echo "== GitHub: BOT_TOKEN =="
echo "   used by: preflight tag checks, publish.sh push, create-release, mirror-public"
for repo in api-client-go api-client-java api-client-python api-client-ruby api-client-typescript; do
  # push also covers creating tags and GitHub releases, which create-release needs.
  check_repo_perm "BOT_TOKEN" "${BOT_TOKEN:-}" "launchdarkly/${repo}" "push"
done

echo
echo "== OctoSTS federated token =="
echo "   minted from the ld-openapi-downstream trust policy in launchdarkly/.github-private"
echo "   used by: preflight (reads gonfalon's spec blob, CI status, changelog)"
echo "            downstream-gonfalon and downstream-terraform-provider (branch + PR)"
# There is no stored secret to inspect here. What can go wrong is the federation
# itself: a policy that does not match, or a repo missing from its `repositories`
# allowlist. Checked via /installation/repositories, which enumerates exactly what
# the minted token is scoped to.
#
# NOT via `.permissions` on the repo endpoint: that field reports a *user's* role
# (push/pull/admin), and an App installation token has no role, only granular
# permissions — so it always reads as empty and every check would fail.
if [ -z "${STS_TOKEN:-}" ]; then
  bad "OctoSTS: no federated token was minted. Check the octosts-action step and that .github/launchdarkly/ld-openapi-downstream.sts.yaml in launchdarkly/.github-private matches this workflow."
else
  required=(launchdarkly/gonfalon)
  if [ "${REQUIRE_DOWNSTREAM_TOKEN}" = "true" ]; then
    required+=(launchdarkly/terraform-provider-launchdarkly)
  else
    skip "OctoSTS token on terraform-provider-launchdarkly: downstream PRs are disabled for this run"
  fi

  if scoped=$(GH_TOKEN="${STS_TOKEN}" gh api /installation/repositories --paginate --jq '.repositories[].full_name' 2>/dev/null) && [ -n "${scoped}" ]; then
    for repo in "${required[@]}"; do
      if grep -qxF "${repo}" <<<"${scoped}"; then
        ok "OctoSTS token is scoped to ${repo}"
      else
        bad "OctoSTS token cannot reach ${repo} — add it to the policy's 'repositories' list. In scope: $(paste -sd, - <<<"${scoped}")"
      fi
    done
    # An installation token's permission set cannot be introspected over the API,
    # so contents/pull_requests write is only proven when a PR is actually opened.
    unver "OctoSTS token: permission level (contents and pull_requests write) cannot be read back; it is proven only when a downstream PR is opened"
  else
    # Fall back to reachability if that endpoint is unavailable — still catches a
    # repo missing from the allowlist, which is the common failure.
    for repo in "${required[@]}"; do
      if GH_TOKEN="${STS_TOKEN}" gh api "repos/${repo}" >/dev/null 2>&1; then
        ok "OctoSTS token can reach ${repo}"
      else
        bad "OctoSTS token cannot reach ${repo} — check the policy's 'repositories' list"
      fi
    done
    unver "OctoSTS token: could not enumerate scope via /installation/repositories; fell back to per-repo reachability"
  fi
fi

echo
echo "== GitHub: BOT_TOKEN on the public mirror target =="
echo "   used by: mirror-public (squash push to launchdarkly/ld-openapi)"
if [ "${REQUIRE_MIRROR_TOKEN}" = "true" ]; then
  check_repo_perm "BOT_TOKEN" "${BOT_TOKEN:-}" "launchdarkly/ld-openapi" "push"
else
  skip "BOT_TOKEN on launchdarkly/ld-openapi: mirroring is disabled for this run"
fi

# --- Registries ---------------------------------------------------------------
echo
echo "== Registries =="

if [ -z "${NPM_TOKEN:-}" ]; then
  bad "NPM_TOKEN: secret is not set"
elif user=$(curl -s -f -H "Authorization: Bearer ${NPM_TOKEN}" https://registry.npmjs.org/-/whoami | jq -r '.username' 2>/dev/null) && [ -n "${user}" ]; then
  ok "NPM_TOKEN: authenticates as ${user}"
else
  bad "NPM_TOKEN: rejected by registry.npmjs.org/-/whoami"
fi

# RubyGems API keys are scoped. A key scoped to push_rubygem — all that releasing
# needs, and the right level of privilege — is rejected by the profile endpoint,
# so a read check there says nothing useful about whether the key can publish.
# There is no read-only endpoint a push-only key can pass, so don't pretend.
if [ -n "${RUBYGEM_API_KEY:-}" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: ${RUBYGEM_API_KEY}" \
    https://rubygems.org/api/v1/profile/me.json || echo 000)
  if [ "${code}" = "200" ]; then
    ok "RUBYGEM_API_KEY: authenticates (profile readable, so the key is broadly scoped)"
  else
    unver "RUBYGEM_API_KEY: set; profile endpoint returned HTTP ${code}, which is expected for a push-only scoped key and does not indicate a problem"
  fi
else
  bad "RUBYGEM_API_KEY: secret is not set"
fi

# PyPI has no read-only token introspection endpoint; the only way to exercise an
# upload token is to upload. Presence is all we can assert.
if [ -n "${PYPI_TOKEN:-}" ]; then
  unver "PYPI_TOKEN: set, but PyPI offers no read-only way to validate an upload token"
else
  bad "PYPI_TOKEN: secret is not set"
fi

if [ -n "${CENTRAL_PORTAL_USERNAME:-}" ] && [ -n "${CENTRAL_PORTAL_PASSWORD:-}" ]; then
  bearer=$(printf '%s:%s' "${CENTRAL_PORTAL_USERNAME}" "${CENTRAL_PORTAL_PASSWORD}" | base64 | tr -d '\n')
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer ${bearer}" \
    'https://central.sonatype.com/api/v1/publisher/deployments?size=1' || echo 000)
  case "${code}" in
    200) ok "CENTRAL_PORTAL_*: authenticates to central.sonatype.com" ;;
    401|403) bad "CENTRAL_PORTAL_*: rejected by central.sonatype.com (HTTP ${code})" ;;
    # Anything else means the request shape was wrong, not the credentials. The
    # portal has no documented whoami, so this is best-effort only.
    *) unver "CENTRAL_PORTAL_*: set; portal returned HTTP ${code} to a best-effort probe, which reflects the probe rather than the credentials" ;;
  esac
else
  bad "CENTRAL_PORTAL_USERNAME/PASSWORD: not set"
fi

# --- LD API key used by the CI sample programs --------------------------------
echo
echo "== LaunchDarkly API =="
echo "   used by: ci.yml sample programs (create + delete a flag in the 'openapi' project)"
if [ -z "${LD_API_KEY:-}" ]; then
  bad "LD_API_KEY: secret is not set"
else
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: ${LD_API_KEY}" \
    https://app.launchdarkly.com/api/v2/projects/openapi || echo 000)
  case "${code}" in
    200) ok "LD_API_KEY: can read the 'openapi' project" ;;
    401) bad "LD_API_KEY: unauthorized" ;;
    403) bad "LD_API_KEY: forbidden on the 'openapi' project" ;;
    404) bad "LD_API_KEY: the 'openapi' project is not visible to this token" ;;
    *) unver "LD_API_KEY: HTTP ${code} from the projects endpoint" ;;
  esac
  # The samples create and delete flags; a read-only token passes the check above
  # but fails in CI, so flag that this audit cannot prove write access.
  unver "LD_API_KEY: write access (samples create/delete flags) cannot be checked without writing"
fi

# --- Report -------------------------------------------------------------------
summary() {
  echo "### Token audit"
  echo
  echo "| Result | Count |"
  echo "|---|---|"
  echo "| PASS | ${#pass[@]} |"
  echo "| FAIL | ${#fail[@]} |"
  echo "| UNVERIFIED | ${#unverified[@]} |"
  echo "| SKIP | ${#skipped[@]} |"
  if [ ${#fail[@]} -gt 0 ]; then
    echo
    echo "**Failures**"
    printf -- '- %s\n' "${fail[@]}"
  fi
  if [ ${#unverified[@]} -gt 0 ]; then
    echo
    echo "**Unverified** (no read-only check exists; these can only fail at publish time)"
    printf -- '- %s\n' "${unverified[@]}"
  fi
}

echo
echo "-----"
echo "PASS ${#pass[@]}  FAIL ${#fail[@]}  UNVERIFIED ${#unverified[@]}  SKIP ${#skipped[@]}"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && summary >> "${GITHUB_STEP_SUMMARY}"

if [ ${#fail[@]} -gt 0 ]; then
  echo
  echo "Credentials needing attention:" >&2
  printf '  %s\n' "${fail[@]}" >&2
  exit 1
fi

echo "All checkable credentials are good."
