# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## What this repo is

A code *generator*, not a library. It turns LaunchDarkly's OpenAPI spec into REST API client libraries for Go, Java, Python, Ruby, and TypeScript, then pushes each generated client into its own public `launchdarkly/api-client-<lang>` repo and publishes to the language package registry.

Two consequences that shape everything:

1. **The spec is not in the repo.** `make` downloads it from `https://app.launchdarkly.com/api/v2/openapi.json` at build time, so build output depends on what is currently deployed to production. `make SPEC_FILE=path` builds from a file instead; `release.yml` uses that to build exactly the spec preflight verified.
2. **Almost all client code is generated.** The only hand-written, committed artifacts are the Makefile, the mustache template overrides, the samples, and the release scripts. Client source appears under `targets/` (gitignored) after a build.

## Build

Requires `java`, `curl`, `jq`. The generator jar is downloaded to the repo root on first build.

```bash
make                    # all clients + both HTML doc targets
make go                 # single target: go | java | python | ruby | typescript-axios
make html html2         # doc targets only
make targets_docker     # run `make all` in the release container image (matches CI)
make clean              # rm -rf targets/ client-clones/
```

Output layout (all gitignored):

- `targets/openapi.json` — downloaded spec, the input to every generator run
- `targets/api-client-<target>/` — generated client
- `targets/html/`, `targets/html2/` — generated API docs
- `targets/build/api-client-<target>/` — throwaway copy used by `build_clients`/`publish`, so build artifacts never land in a source tree

Version comes from `LD_RELEASE_VERSION` (default `0.0.1-SNAPSHOT`); `TAG` defaults to it.

## Verifying a change

No unit test suite. Validation is three layers.

**1. Static checks over the release automation** — seconds, no side effects:

```bash
./scripts/release/selfcheck.sh
```

Every check corresponds to a defect that shipped and cost a dispatch-and-wait cycle: a job minting a federated token without `id-token: write`; an API call the trust policy doesn't permit; a token-scope pattern that can never match; a downstream target missing from its allowlist; a referenced secret that doesn't exist; an input passed to a pinned action that the action doesn't declare; a `make` dry-run target that is a silent no-op; `mapfile`/bare `sed -i`, which break on macOS bash 3.2.

Two rules it enforces about itself, both learned the hard way:

- **A check that verified nothing reports SKIP or FAIL, never PASS.** Several checks derive a count by extracting from the workflows, and a zero there means the extractor broke far more often than it means the repo is clean — so they cross-check against the raw file text and fail on a mismatch.
- **An unrecognised API endpoint is a failure, not an assumed pass.** When adding a call made with the federated token, add its endpoint to the endpoint→permission table. That table is what turns a would-be 403 into a local error.

Checks needing credentials self-skip, so it is useful in CI with less coverage.

**2. Does the generated code compile and package?**

```bash
LD_RELEASE_VERSION=0.0.1 make
make BUILD_TARGETS="go java python ruby typescript-axios" build_clients
```

`build_clients` runs `scripts/build/<target>.sh` per target. Narrow it while iterating: `make BUILD_TARGETS=go build_clients`.

**3. Does the client work against the API?** Each `samples/<target>/` program creates a multivariate flag `test-<lang>`, prints it, and deletes it — live integration tests needing `LD_API_KEY`. Run one after `make <target>`:

```bash
cd samples/go && make
cd samples/python && pip install -e ../../targets/api-client-python && python main.py
cd targets/api-client-ruby && gem build launchdarkly_api.gemspec && gem install ./launchdarkly_api*.gem && cd ../../samples/ruby && ruby main.rb
cd targets/api-client-java && mvn clean install && cd ../../samples/java && mvn clean install exec:java   # pom.xml has an API_CLIENT_VERSION placeholder CI seds
cd targets/api-client-typescript-axios && npm install && npm run build && npm link && cd ../../samples/typescript-axios && npm link launchdarkly-api-typescript && npm install && npm run build && npm start
```

Sample code is spliced into each client's README, so sample edits change published docs.

## Architecture notes

### Template overrides (`swagger-codegen-templates/`)

Only the HTTP-layer file per language is overridden; everything else uses stock generator templates. Each override is a **verbatim copy of the upstream generator template** with additions fenced by `// CUSTOM-START` / `// CUSTOM-END`, injecting the default `LD-API-Version` header (and, for TypeScript, `X-LaunchDarkly-User-Agent`).

**When bumping `GENERATOR_VERSION` you must re-copy the upstream templates and re-apply the CUSTOM blocks** — otherwise the override silently pins old generator behaviour. The Makefile header lists the upstream URL for each file.

### Two versions that move independently

- `GENERATOR_VERSION` — openapi-generator release used
- `LATEST_API_VERSION` (e.g. `20240415`) — the API version the spec corresponds to, baked into every client as the default `LD-API-Version` header. Update it when the spec's API version changes, or clients keep sending a stale header.

Per-language flags live in `CODEGEN_PARAMS_<target>` — package names, registry metadata, and each language's version convention (Go uses only the major from `TAG`; others the full `TAG`).

**Client dependency versions float, so a third-party release can break the build with no change here.** That has happened: `axios` is pinned to an exact `1.18.1` because 1.19.0 broke the TypeScript client's build. See the comment above `CODEGEN_PARAMS_typescript-axios` for the cause and the revert condition. Nothing builds on a schedule, so the next PR is what discovers such breakage.

### Release plumbing (`Makefile` + `scripts/release/`)

- `make push` — clones each public `api-client-<target>` repo into `client-clones/`, wipes it, copies the generated client in, commits, tags, pushes. Go is tagged `v$(TAG)`; every other target `$(TAG)` bare. Rehearse with `make push_dry_run` (real clone + commit, `git push --dry-run`) or `make push_test` (echoes git commands).
- The TypeScript target is named `typescript-axios`, so `push` clones `launchdarkly/api-client-typescript-axios` — that repo was renamed to `api-client-typescript` and GitHub redirects the old name. Both work; don't "fix" the apparent mismatch with `release.yml`'s `create-release` matrix.
- Non-Go client repos end up with **two tags per release**: bare `X.Y.Z` from `make push`, and `vX.Y.Z` created by `create-release`. Go gets only `vX.Y.Z`.
- `make publish` — pushes artifacts to PyPI, RubyGems, npm, and Maven Central. Go has no registry step; its **tag is the release**.
- `scripts/release/prepare.sh` writes registry credentials. Deliberately set up *after* build/test so build scripts cannot push.
- `push_dry_run` needs its `push` prerequisite; without it the target is only variable assignments, so `make` reports "Nothing to be done" and exits 0 — a rehearsal that silently does nothing. The `release-dry-run/*.sh` scripts also need `LD_RELEASE_ARTIFACTS_DIR` set or they fail on `mkdir`.

## Releasing client libraries

`release.yml` automates the release runbook end to end (the process and its rationale are documented internally). Dispatch it with **no inputs** — version, bump type, and release notes are derived, and each precondition is an enforced gate that aborts with a specific reason.

### The release PR

Normally nobody dispatches anything. `release-pr.yml` runs hourly (or on a `gonfalon-spec-deployed` repository dispatch) and keeps one `chore: release X.Y.Z` PR open on branch `release/next`. It changes only `release-manifest.json` (version, plus the gonfalon commit and blob SHA of the spec production serves) and `CHANGELOG.md`. CI runs on it like any PR. **Merging it is the release:** the push changes `release-manifest.json`, which starts `release.yml` with every optional job on. Preflight (`RELEASE_MANIFEST`) takes the version and notes from the PR, fetches the spec from that gonfalon commit, checks its blob SHA, and hands those bytes to the build.

- **The spec is pinned by gonfalon commit, not committed here.** gonfalon commits the published spec and production serves it byte for byte. `release-manifest.json` on main names the last release's commit, which is the baseline the next release PR diffs against.
- **The bot owns `release/next`** and force-pushes it on every sync. Fix notes in gonfalon's `apidocs/CHANGELOG.md`; override the bump with a `release:major`, `release:minor` or `release:patch` label (applies on the next sync, or dispatch `release-pr.yml`).
- **An approval covers one release:** the `release-manifest.json` at the commit it approved. main's rules keep approvals through a push, so every sync dismisses approvals whose manifest differs from the release it now offers (picking up main, or the heading's date moving, leaves the manifest alone and keeps them). As a backstop, preflight on a push fails unless the commit merged a `release/next` PR with an approval under the same rule, i.e. of the manifest that merged.
- **The bump comes from the spec** (`scripts/release/sync-release-pr.sh`): major if oasdiff finds a breaking change or `client-surface.py` finds a removed or renamed schema, operationId or tag (those rename generated types, methods and API classes without changing the wire); minor for any other API change; patch for descriptions only. Diff against gonfalon's file, never the `api/openapi.yaml` bundled in api-client-go: openapi-generator rewrites it, so names look removed that never existed.
- **Notes are the gonfalon changelog entries added since the last release's gonfalon commit** (`release-notes.py`), so they are right whether or not gonfalon's changelog PR for the last release has merged.
- **The PR's CI tests production's spec as of the CI run**, which a deploy after the last sync can make newer than the manifest until the next sync. The release always ships the manifest's spec.
- `release-pr.yml` pushes with the `ld-openapi-release-pr` OctoSTS identity, not `GITHUB_TOKEN`: pushes made with `GITHUB_TOKEN` start no workflows, so CI would never run on the PR. Its policy is in this repo (`.github/launchdarkly/`, read from main); `ld-openapi-spec-read`, for gonfalon, is in launchdarkly/.github-private.
- **To retry a release PR's release, dispatch `release.yml` with `fromManifest`** (plus `force` if the failed attempt left tags). It releases exactly what the manifest on main records, as the push did. A dispatch without it derives everything from production and gonfalon main, which may have moved on.
- **A release dispatched without `fromManifest` does not update `release-manifest.json`.** The next sync then fails, naming the newer `api-client-go` tag, rather than offering that release again. Set the manifest to what Preflight's summary prints. Merging that change starts `release.yml`, whose preflight stops it because no release PR was merged.
- Dispatching with `dryRun` rehearses, as before.

All inputs are optional escape hatches: `releaseVersion` (bare semver), `bumpType`, `dryRun`, `force` (delete tags left by a failed attempt), `openDownstreamPr`, `mirrorPublic`, `skipCiGate`, `skipSpecParity`, `fromManifest`.

### Job graph

(`preflight`, `token-audit`) → `release` → `verify-published` → (`create-release`, downstream PR jobs, `mirror-public`)

`scripts/release/preflight.sh` does the derivation and gating, and runs locally given a token with read access to the spec's source repo.

- **Gate 1 — spec parity** (bypass with `skipSpecParity`). The spec's source repo commits the published spec, and production serves that file byte for byte, so comparing git blob SHAs settles whether production is caught up and nothing is mid-flight. Compared by blob SHA rather than downloading both copies, because the file is ~2.8 MB — over the contents API's 1 MB raw limit — while the tree API always returns a blob SHA. On a mismatch it names the commit production is serving and the one it is waiting for. The build ships production's bytes either way, so `skipSpecParity` changes only whether the run refuses to proceed — but version and notes still come from the source repo's tip, so the notes may then describe merged-but-undeployed changes.
- **Gate 2 — source repo CI green**, pinned to the commit parity resolved to. Uses check-runs only; the combined-status endpoint needs a permission the token isn't granted.
- **Gate 3 — no tag collisions** from a partial release, in any client repo, for either tag form.

Everything read from the source repo is pinned to the one commit Gate 1 settled on. Its default branch moves often enough that reading the spec and the notes at separate moments can pair notes with a spec they don't describe.

**Bump inference** comes from the `### ` headings of the source repo's unreleased changelog section: `Removed`/`Changed` → major, `Added`/`Deprecated` → minor, `Bug Fixes`/`Fixed`/`Security` → patch. `### Changed` is genuinely ambiguous, so the rule errs toward major; override with `bumpType`. An unrecognised heading aborts rather than guesses.

### Post-release jobs

- `verify-published` polls PyPI, RubyGems and npm as **hard** failures, plus the Go module proxy and Maven Central as **soft** warnings, then checks client repo tags. The Go proxy is soft on purpose: Go has no publish step, the tag is checked directly, and the proxy caches *negative* lookups — so a `go get` for a version before it exists (a rehearsal, say) makes it serve "unknown revision" for a while afterwards. That failed this job once on an otherwise complete release. It checks `v<version>` on Go and a **bare `<version>`** elsewhere, since that is all `make push` has created by then.
- Two downstream jobs bump the published client in the repos that consume it, each through that repo's own `make update-api-client-go`. Keeping each codemod in the repo it edits means the logic lives beside the imports it rewrites. The terraform provider's runs here through `pr-downstream`. gonfalon's runs in gonfalon: `dispatch-gonfalon-bump.sh` dispatches its `update-api-client-go.yml` (with the `ld-openapi-gonfalon-dispatch` token) and waits for it, because the bump needs gonfalon's CI setup (private modules through its content cache, its Bazel config), which a runner here kept lacking. Neither auto-merges: a major bump moves the Go module path (`api-client-go/vN`), so it rewrites imports across dozens to hundreds of files, and most API releases are major.
- A third downstream job records the release in gonfalon's `apidocs/CHANGELOG.md`, as its own PR so it does not wait on the bump's review. `gonfalon-changelog.py` moves only the entries this release shipped (its notes) from `[Unreleased]` into `## [X.Y.Z]`; entries merged after the release's gonfalon commit stay under `[Unreleased]`. A released entry that was edited in gonfalon since is recorded with its released text, and the job comments on the PR so someone can reconcile the two.
- **The downstream jobs are skipped on a rehearsal.** The pinned `pr-downstream` version has no `dryrun` input, so passing one was silently ignored and a rehearsal was attempting real PR creation. They also can't be meaningfully rehearsed: they bump *to* the version being released, which does not exist until it is published.
- **Reviewers are requested as a user, not a team.** A federated App installation token cannot request team reviewers. CODEOWNERS in each downstream repo still pulls in the owning team.
- `mirror-public` opens (or updates) a PR on the public `launchdarkly/ld-openapi`, from branch `mirror/sync`: one commit whose tree is private main's. The public main requires a PR, and that content becomes public, so a person merges it. **It aborts if the public repo has changes that did not come from here** (its tree matches no commit on private main); bring such changes into this repo first. It is its own workflow (`mirror-public.yml`), which `release.yml` calls and which can be dispatched to retry a failed mirror without releasing again. It pushes with the `ld-openapi-mirror` OctoSTS token (launchdarkly/.github-private), not `BOT_TOKEN`: a PAT cannot push workflow files without the `workflow` scope, and the sync usually changes some. Failure here does not invalidate the release.
- This repo's workflows are mirrored too, and Actions runs in the public repo, so anything that needs this repo's credentials is guarded with `github.repository == 'launchdarkly/ld-openapi-private'`: the release, the release PR sync, and the nightly CI run. Keep that guard on any new scheduled or push-triggered job.

### Credentials

`BOT_TOKEN` needs push on all five `api-client-*` repos; the registry credentials need publish rights; `LD_API_KEY` needs write on the project the samples use. Anything touching the spec's source repo or the downstream repos uses a token **minted at runtime**, not a stored secret.

Stored secrets are managed in internal infrastructure, not here. Where a parameter is created holding a placeholder and the real value written separately, there is a window where the secret exists but is the placeholder — the audit detects that and names it, rather than reporting an opaque authentication failure.

`token-audit.yml` audits every credential read-only and is dispatchable on its own. `release.yml` runs it as a gate on **every** release: a bad registry credential would otherwise surface only after `make push` had tagged five client repos, which is what forces the delete-the-tags-and-retry dance.

Two registry credentials cannot be positively verified and report `UNVERIFIED`, which is not a failure: PyPI has no token introspection, and a correctly-scoped RubyGems key (push-only) is rejected by the profile endpoint by design.

**Every job that mints a federated token needs `permissions: id-token: write`.** Without it the exchange fails before it reaches the trust policy. For a reusable workflow it must be granted **twice** — on the calling job and at the called workflow's own level — because a reusable workflow is capped by what its caller holds.

### Rehearsing

`dryRun: true` runs the audit, preflight, and the full build, uses `push_dry_run`/`publish_dry_run`, and skips the downstream PR jobs. The artifacts a real run would have published are uploaded as `dry-run-artifacts`.

**A rehearsal's log looks almost identical to a real release.** `push_dry_run` does real clones, commits and local tags, and `git push --dry-run` prints the same `* [new tag]` lines a real push does; `npm publish --dry-run` prints its usual notices. The distinguishing markers are `(dry-run)` in the npm output and "Simulating the updates we would do" from `make`. When in doubt, verify against the world — repo tags and registry HTTP status — rather than trusting the log's appearance.

`push_dry_run` does authenticate and check write access, so it genuinely exercises `BOT_TOKEN`'s push rights.

### Testing changes to these workflows

`workflow_dispatch` only registers if the workflow file carrying that trigger exists on **`main`**. A new workflow, or a newly added trigger on an existing one, is therefore not dispatchable until merged. `release.yml` itself is dispatchable from any branch and GitHub runs the definition from the branch you select — **except** the federated-token steps, whose trust policy is restricted to `main`. Anything needing a minted token only works there. `ci.yml` runs on every PR regardless.

### Troubleshooting

- `Access Denied` fetching `openapi.json` — that endpoint fails intermittently; re-run.
- Publish failure to one registry — **published registry versions are immutable.** A partial publish cannot be re-run; it needs a new patch version. Before re-running anything, establish what actually landed: repo tags and each registry's HTTP status. `force: true` deletes tags from a prior attempt but cannot un-publish.
- Re-running a run: use **re-run failed jobs**, never re-run all, or the publish job repeats against registries that already hold the version.
- Gate 1 timing out — either the spec commit has not deployed, or spec changes keep landing. Waiting is the correct default; `skipSpecParity` is the override.
- A healthy run takes ~6 min through publish. Much longer means something is hanging.

## Conventions

- Never edit generated output under `targets/` to fix a problem; change the spec, the template override, or the `CODEGEN_PARAMS_<target>` flags.
- This repo is kept in sync with the public `launchdarkly/ld-openapi`, so treat everything committed here as publishable.
