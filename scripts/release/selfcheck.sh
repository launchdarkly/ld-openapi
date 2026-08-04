#!/usr/bin/env bash
#
# Static checks over the release automation, runnable locally in seconds.
#
#   ./scripts/release/selfcheck.sh
#
# Exists because every failure in this automation so far was discoverable without
# running a release, but nothing was checking for it. Each check below corresponds
# to a defect that actually shipped and cost a dispatch-and-wait cycle:
#
#   OIDC          a job used octosts-action without id-token: write
#   POLICY-PERM   the CI gate called an endpoint the trust policy did not permit
#   POLICY-MATCH  a job_workflow_ref pattern that could never match (unanchored)
#   POLICY-REPOS  a downstream target missing from the policy's allowlist
#   SECRETS       a workflow referenced a secret that did not exist
#   DRYRUN        a make dry-run target that was a silent no-op
#   PORTABILITY   mapfile / bare sed -i, which break on macOS bash 3.2
#
# Checks needing the trust policy are SKIPped when it is unreachable (it lives in
# the private launchdarkly/.github-private), so this is useful in CI too, just
# with less coverage. Point POLICY_FILE at a local checkout to get the full set.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

REPO=launchdarkly/ld-openapi-private
POLICY_REPO=launchdarkly/.github-private
POLICY_PATH=.github/launchdarkly/ld-openapi-downstream.sts.yaml
POLICY_FILE=${POLICY_FILE:-$HOME/code/launchdarkly/.github-private/${POLICY_PATH}}

# Scripts this automation owns. The per-target publish scripts predate it and
# carry unused-positional-arg warnings that are part of their interface.
OWNED_SCRIPTS=(
  scripts/release/preflight.sh
  scripts/release/token-audit.sh
  scripts/release/verify-published.sh
  scripts/release/mirror-public.sh
  scripts/release/gonfalon-update.sh
  scripts/release/publish.sh
  scripts/release/selfcheck.sh
)

pass=0; fail=0; skip=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }
nope() { echo "  SKIP  $1"; skip=$((skip+1)); }

# Resolve the trust policy: local checkout, else the API, else skip.
#
# Two traps here, both of which have bitten:
#   - `|| true` on the fetch keeps a failed request's response body. A GitHub API
#     error body is valid YAML, so it parses into a dict with none of the keys the
#     checks read, and they then "fail" against something that is not a policy.
#     With a token that cannot see the policy repo - CI, for one - that is the
#     normal case, not an edge case.
#   - so the fetch must respect gh's exit status AND the result must be shape-checked
#     before use. Anything that is not recognisably a trust policy means SKIP.
policy=""
policy_problem=""
if [ -f "${POLICY_FILE}" ]; then
  policy=$(cat "${POLICY_FILE}")
elif command -v gh >/dev/null 2>&1; then
  if fetched=$(gh api "repos/${POLICY_REPO}/contents/${POLICY_PATH}" \
      -H "Accept: application/vnd.github.raw" 2>/dev/null); then
    policy="${fetched}"
  fi
fi
if [ -n "${policy}" ]; then
  for key in subject_pattern claim_pattern permissions repositories; do
    grep -qE "^${key}:" <<<"${policy}" || policy_problem="${policy_problem} ${key}"
  done
  if [ -n "${policy_problem}" ]; then
    policy=""
    policy_problem="fetched a response that is not a trust policy (missing:${policy_problem})"
  fi
fi

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  if out=$(shellcheck -S warning "${OWNED_SCRIPTS[@]}" 2>&1); then
    ok "no warnings in ${#OWNED_SCRIPTS[@]} owned scripts"
  else
    bad "shellcheck warnings:"
    sed 's/^/        /' <<<"${out}" | head -20
  fi
else
  nope "shellcheck not installed"
fi

echo
echo "== PORTABILITY: constructs that break on macOS bash 3.2 / BSD sed =="
# This file necessarily contains the patterns it searches for, so exclude it.
port_targets=()
for f in "${OWNED_SCRIPTS[@]}"; do [ "${f}" = "scripts/release/selfcheck.sh" ] || port_targets+=("${f}"); done
port_hits=$(grep -nE '(^|[^-])\bmapfile\b|sed -i +[^.'"'"'"]' "${port_targets[@]}" 2>/dev/null || true)
if [ -z "${port_hits}" ]; then
  ok "no mapfile, no bare 'sed -i'"
else
  bad "non-portable constructs:"
  sed 's/^/        /' <<<"${port_hits}"
fi

echo
echo "== OIDC: every octosts-action step has id-token: write =="
oidc=$(python3 - <<'PY'
import yaml, glob, os, sys
problems, checked = [], 0
wf = {os.path.basename(p): yaml.safe_load(open(p)) for p in glob.glob('.github/workflows/*.yml')}

def grants(doc, job):
    for src in (job.get('permissions'), doc.get('permissions')):
        if isinstance(src, dict) and src.get('id-token') == 'write':
            return True
    return False

for fname, doc in wf.items():
    for jname, job in (doc.get('jobs') or {}).items():
        uses_sts = any('octosts-action' in str(s.get('uses', '')) for s in (job.get('steps') or []))
        if uses_sts:
            checked += 1
            if not grants(doc, job):
                problems.append(f"{fname}/{jname} runs octosts-action without id-token: write")
        # A reusable-workflow call is capped by the caller's permissions.
        called = str(job.get('uses', ''))
        if called.startswith('./'):
            target = wf.get(os.path.basename(called))
            if target and any(
                'octosts-action' in str(s.get('uses', ''))
                for tj in (target.get('jobs') or {}).values()
                for s in (tj.get('steps') or [])
            ):
                checked += 1
                if not grants(doc, job):
                    problems.append(f"{fname}/{jname} calls {os.path.basename(called)} (which mints a token) without granting id-token: write")
print(f"CHECKED {checked}")
for p in problems:
    print(f"PROBLEM {p}")
PY
)
n=$(grep -oE 'CHECKED [0-9]+' <<<"${oidc}" | awk '{print $2}')
# If the raw YAML mentions octosts-action but the parser found no minting job, the
# extractor is broken and a pass would be meaningless.
raw_sts=$(grep -rlc 'octosts-action' .github/workflows/*.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "${n:-0}" = "0" ] && [ "${raw_sts}" != "0" ]; then
  bad "workflows reference octosts-action but no token-minting job was detected — the check is broken"
elif grep -q PROBLEM <<<"${oidc}"; then
  bad "id-token gaps:"
  grep PROBLEM <<<"${oidc}" | sed 's/PROBLEM /        /'
else
  ok "${n:-0} token-minting job(s), all grant id-token: write"
fi

echo
echo "== POLICY-MATCH: the trust policy matches this repo's workflows on main =="
if [ -z "${policy}" ]; then
  nope "trust policy unavailable: ${policy_problem:-not found locally and not readable via gh} (set POLICY_FILE, or authenticate gh against ${POLICY_REPO})"
else
  match=$(POLICY="${policy}" REPO="${REPO}" python3 - <<'PY'
import os, re, yaml, glob
pol = yaml.safe_load(os.environ['POLICY']); repo = os.environ['REPO']
# octo-sts compiles claim patterns anchored: regexp.Compile("^" + v + "$")
jr = re.compile("^" + pol['claim_pattern']['job_workflow_ref'] + "$")
sr = re.compile("^" + pol['subject_pattern'] + "$")
problems = []
if not sr.match(f"repo:{repo}:ref:refs/heads/main"):
    problems.append(f"subject_pattern does not match a dispatch on main")
minting = []
for p in glob.glob('.github/workflows/*.yml'):
    doc = yaml.safe_load(open(p))
    if any('octosts-action' in str(s.get('uses',''))
           for j in (doc.get('jobs') or {}).values() for s in (j.get('steps') or [])):
        minting.append(os.path.basename(p))
for f in sorted(minting):
    claim = f"{repo}/.github/workflows/{f}@refs/heads/main"
    if not jr.match(claim):
        problems.append(f"job_workflow_ref does not match {claim}")
print(f"CHECKED {len(minting)}")
for p in problems: print("PROBLEM " + p)
PY
)
  if grep -q PROBLEM <<<"${match}"; then
    bad "policy would deny these:"
    grep PROBLEM <<<"${match}" | sed 's/PROBLEM /        /'
  else
    ok "$(grep -oE 'CHECKED [0-9]+' <<<"${match}" | awk '{print $2}') minting workflow(s) match on refs/heads/main"
  fi
fi

echo
echo "== POLICY-PERM: the policy permits every gonfalon endpoint preflight calls =="
if [ -z "${policy}" ]; then
  nope "trust policy unavailable${policy_problem:+: ${policy_problem}}"
else
  # Endpoint -> required GitHub App permission. Hand-maintained; extend it when a
  # new endpoint is called. This is the check that catches a 403 before CI does.
  perm=$(POLICY="${policy}" python3 - <<'PY'
import os, re, yaml
pol = yaml.safe_load(os.environ['POLICY'])
granted = pol.get('permissions') or {}
RULES = [
    (r'/commits/[^/"]+/status',      'statuses'),
    (r'/commits/[^/"]+/check-runs',  'checks'),
    (r'/git/trees/',                 'contents'),
    (r'/contents/',                  'contents'),
    (r'/commits\?path=',            'contents'),   # list commits touching a path
    (r'/commits/main',               'contents'),
]
src = open('scripts/release/preflight.sh').read()
# Join backslash line-continuations first. Without this, a call whose URL sits on
# the next line is invisible to the extractor — so it is neither validated nor
# reported as unrecognised, which is precisely the silent gap this table exists to
# close. One such call shipped before this was fixed.
src = re.sub(r'\\\n\s*', ' ', src)
# Only calls routed through the gonfalon token are governed by this policy.
calls = re.findall(r'gh_gonfalon api\s+"([^"]+)"', src)
if not calls:
    print("PROBLEM found no gh_gonfalon calls at all — the extractor is broken")
problems, seen = [], set()
for c in calls:
    for pattern, need in RULES:
        if re.search(pattern, c):
            seen.add(need)
            if need not in granted:
                problems.append(f"{c} needs '{need}' but the policy grants: {sorted(granted)}")
            break
    else:
        problems.append(f"{c} is not in selfcheck's endpoint->permission table; add it")
print(f"CHECKED {len(calls)} call(s), permissions needed: {sorted(seen)}")
for p in sorted(set(problems)): print("PROBLEM " + p)
PY
)
  echo "        $(grep -oE 'CHECKED.*' <<<"${perm}")"
  if grep -q PROBLEM <<<"${perm}"; then
    bad "permission gaps:"
    grep PROBLEM <<<"${perm}" | sed 's/PROBLEM /        /'
  else
    ok "every gonfalon endpoint is covered by the policy's permissions"
  fi
fi

echo
echo "== POLICY-REPOS: every downstream target is in the policy allowlist =="
if [ -z "${policy}" ]; then
  nope "trust policy unavailable${policy_problem:+: ${policy_problem}}"
else
  targets=$(grep -oE 'repository: launchdarkly/[a-z0-9._-]+' .github/workflows/release.yml | awk '{print $2}' | sort -u)
  allowed=$(POLICY="${policy}" python3 -c "
import os, yaml
print('\n'.join('launchdarkly/' + r for r in (yaml.safe_load(os.environ['POLICY']).get('repositories') or [])))")
  missing=""
  for t in ${targets}; do grep -qxF "${t}" <<<"${allowed}" || missing="${missing} ${t}"; done
  if [ -z "${targets}" ]; then
    bad "found no pr-downstream targets in release.yml — the extraction is broken"
  elif [ -n "${missing}" ]; then
    bad "pr-downstream targets absent from the policy's repositories:${missing}"
  else
    ok "all pr-downstream targets allowed ($(tr '\n' ' ' <<<"${targets}"))"
  fi
fi

echo
echo "== SECRETS: every secret the workflows reference exists on the repo =="
if command -v gh >/dev/null 2>&1 && actual=$(gh api "repos/${REPO}/actions/secrets" --jq '.secrets[].name' 2>/dev/null) && [ -n "${actual}" ]; then
  referenced=$(grep -rhoE 'secrets\.[A-Z0-9_]+' .github/workflows/ | cut -d. -f2 | sort -u)
  missing=""
  for s in ${referenced}; do
    [ "${s}" = "GITHUB_TOKEN" ] && continue
    grep -qxF "${s}" <<<"${actual}" || missing="${missing} ${s}"
  done
  if [ -n "${missing}" ]; then
    bad "referenced but not present as repo secrets (may be org-level — verify):${missing}"
  else
    ok "all referenced secrets exist ($(tr '\n' ' ' <<<"${referenced}"))"
  fi
else
  nope "cannot list repo secrets (needs gh auth with admin on ${REPO})"
fi

echo
echo "== ACTION-INPUTS: every input passed to a pinned action actually exists =="
# A workflow passing an input the action does not declare gets only a warning, which
# nobody reads, and the value is silently ignored. `dryrun: ${{ inputs.dryRun }}` was
# passed to a pinned pr-downstream that has no such input, so rehearsals were
# attempting real PR creation.
if command -v gh >/dev/null 2>&1; then
  ai=$(python3 - <<'PYEOF'
import yaml, glob, os, re, subprocess, sys
problems, checked, unresolved = [], 0, []
for path in glob.glob('.github/workflows/*.yml'):
    doc = yaml.safe_load(open(path))
    for jname, job in (doc.get('jobs') or {}).items():
        for step in (job.get('steps') or []):
            uses, with_ = str(step.get('uses','')), (step.get('with') or {})
            # Only third-party actions pinned to a ref we can resolve.
            if not with_ or '@' not in uses or uses.startswith('./'):
                continue
            repo, ref = uses.rsplit('@', 1)
            if repo.count('/') != 1:
                continue
            try:
                raw = subprocess.run(
                    ['gh','api',f'repos/{repo}/contents/action.yml?ref={ref}',
                     '-H','Accept: application/vnd.github.raw'],
                    capture_output=True, text=True, timeout=25)
                if raw.returncode != 0 or not raw.stdout.strip():
                    unresolved.append(f"{repo}@{ref[:12]}")
                    continue
                declared = set((yaml.safe_load(raw.stdout).get('inputs') or {}).keys())
            except Exception:
                unresolved.append(f"{repo}@{ref[:12]}")
                continue
            checked += 1
            for k in with_:
                if k not in declared:
                    problems.append(f"{os.path.basename(path)}/{jname}: '{k}' is not an input of {repo}@{ref[:12]}")
print(f"CHECKED {checked}")
print(f"UNRESOLVED {len(set(unresolved))} {' '.join(sorted(set(unresolved)))}".rstrip())
for p in sorted(set(problems)): print("PROBLEM " + p)
PYEOF
)
  echo "        $(grep -oE 'CHECKED [0-9]+' <<<"${ai}") pinned action(s) with inputs"
  unresolved=$(grep -oE 'UNRESOLVED [0-9]+.*' <<<"${ai}" | cut -d' ' -f2-)
  if grep -q PROBLEM <<<"${ai}"; then
    bad "inputs that will be silently ignored:"
    grep PROBLEM <<<"${ai}" | sed 's/PROBLEM /        /'
  elif grep -q 'CHECKED 0' <<<"${ai}"; then
    # Passing here would be false assurance: it verified nothing. Needs a token
    # with read access to the action repos (GITHUB_TOKEN suffices; they are public).
    nope "resolved no pinned actions at all, so nothing was verified${unresolved:+ (unresolved: ${unresolved#* })}"
  elif [ "${unresolved%% *}" != "0" ]; then
    nope "some pinned actions could not be resolved and were not verified: ${unresolved#* }"
  else
    ok "all inputs passed to pinned actions are declared by them"
  fi
else
  nope "cannot resolve pinned actions (gh not available)"
fi

echo
echo "== DRYRUN: rehearsal make targets are not silent no-ops =="
for target in push_dry_run publish_dry_run; do
  out=$(make -n "${target}" 2>&1 || true)
  if grep -qi "nothing to be done" <<<"${out}" || [ -z "${out}" ]; then
    bad "make ${target} does nothing — it needs a recipe or a prerequisite"
  else
    ok "make ${target} expands to $(wc -l <<<"${out}" | tr -d ' ') line(s) of recipe"
  fi
done

echo
echo "-----"
echo "PASS ${pass}  FAIL ${fail}  SKIP ${skip}"
[ "${fail}" -eq 0 ] || exit 1
