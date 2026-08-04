# LaunchDarkly OpenAPI

This repository uses the [OpenAPI Generator](https://github.com/OpenAPITools/openapi-generator) library to create LaunchDarkly REST API client libraries from our [OpenAPI spec](https://app.launchdarkly.com/api/v2/openapi.json).

The LaunchDarkly REST API is for custom integrations, data export, or automating feature flag workflows. *DO NOT* use these libraries to add feature flags to web or mobile applications. To integrate feature flags with applications, please see the [SDK documentation](https://docs.launchdarkly.com/sdk).

## Code generation

Server/client code for the API can be automatically generated. To generate the code:

  1. Ensure that you have `java`, `curl`, and `jq` installed.
  1. The default make command will generate all target libraries:
```
> make
```

Generated output lands under `targets/`, which is not committed. To generate a single language, name it as the target — for example `make go`. Valid targets are `go`, `java`, `python`, `ruby`, and `typescript-axios`.

Only the HTTP-layer template is overridden per language, in `swagger-codegen-templates/`. Each override is a verbatim copy of the corresponding upstream generator template with LaunchDarkly additions fenced by `CUSTOM-START` / `CUSTOM-END` markers, so it must be re-copied and re-applied whenever `GENERATOR_VERSION` in the Makefile changes.

## Verifying generated clients

There is no unit test suite. Two checks stand in for one, both run by CI on every pull request:

  1. `make BUILD_TARGETS="go java python ruby typescript-axios" build_clients` — confirms each generated client compiles and packages.
  1. The programs under `samples/` — each creates a feature flag against the live API, prints it, and deletes it, exercising the generated client end to end. They need an API key.

`./scripts/release/selfcheck.sh` runs static checks over the release automation itself, in a couple of seconds and with no side effects.

## How releases work

Releases run from the [`release.yml`](.github/workflows/release.yml) GitHub Actions workflow. Dispatch it with no inputs for a normal release: the version, the semver bump, and the release notes are all derived, and each precondition is an enforced gate that fails with a specific reason rather than releasing on a guess.

A release, in order:

  1. Audits every credential it will need, read-only, before doing any work.
  1. Checks that production is serving the spec the release will be built from, and that the spec's source is in a good state.
  1. Derives the next version from the most recent client tag and the bump implied by the pending changelog entries.
  1. Generates and builds all five clients.
  1. Pushes each client to its own public `launchdarkly/api-client-<language>` repository, tags it, and publishes to PyPI, RubyGems, npm, and Maven Central. Go has no registry step — its git tag is the release.
  1. Confirms each package is actually retrievable from its registry before continuing.
  1. Creates a GitHub release on each client repository, and opens pull requests bumping the new client version in the repositories that consume it.

All workflow inputs are optional overrides. The useful ones:

| Input | Effect |
| --- | --- |
| `dryRun` | Rehearses everything without pushing or publishing anything |
| `releaseVersion` | Releases a specific version instead of the derived one |
| `bumpType` | Forces `major`, `minor`, or `patch` |
| `force` | Deletes tags left behind by a previous failed attempt |

Published registry versions are immutable, so a release that fails partway through cannot simply be re-run — it needs a new patch version. If a run fails, establish what actually reached each registry before retrying, and re-run only the failed jobs so the publish step is not repeated.
