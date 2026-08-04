# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A code *generator*, not a library. It turns LaunchDarkly's OpenAPI spec into REST API client libraries for Go, Java, Python, Ruby, and TypeScript, then pushes each generated client into its own public `launchdarkly/api-client-<lang>` repo and publishes to the language package registry.

Two consequences that shape everything:

1. **The spec is not in the repo.** `make` downloads it from `https://app.launchdarkly.com/api/v2/openapi.json` at build time, so build output depends on what is currently deployed to production.
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

All inputs are optional escape hatches: `releaseVersion` (bare semver), `bumpType`, `dryRun`, `force` (delete tags left by a failed attempt), `openDownstreamPr`, `mirrorPublic`, `skipCiGate`, `skipSpecParity`.

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
- Two downstream PR jobs bump the published client in the repos that consume it, each calling that repo's own `make update-api-client-go`. Keeping each codemod in the repo it edits means the logic lives beside the imports it rewrites. Neither auto-merges: a major bump moves the Go module path (`api-client-go/vN`), so it rewrites imports across dozens to hundreds of files, and most API releases are major.
- **Both downstream jobs are skipped on a rehearsal.** The pinned `pr-downstream` version has no `dryrun` input, so passing one was silently ignored and a rehearsal was attempting real PR creation. They also can't be meaningfully rehearsed: they bump *to* the version being released, which does not exist until it is published.
- **Reviewers are requested as a user, not a team.** A federated App installation token cannot request team reviewers. CODEOWNERS in each downstream repo still pulls in the owning team.
- `mirror-public` squash-mirrors onto the public `launchdarkly/ld-openapi`. **Aborts on conflict rather than resolving** — that push is not practically reversible, and the public repo has diverged. Failure here does not invalidate the release.

### Credentials

`BOT_TOKEN` needs push on all five `api-client-*` repos and on the public `ld-openapi`; the registry credentials need publish rights; `LD_API_KEY` needs write on the project the samples use. Anything touching the spec's source repo or the downstream repos uses a token **minted at runtime**, not a stored secret.

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
