# LaunchDarkly OpenAPI

This repository uses the [OpenAPI Generator](https://github.com/OpenAPITools/openapi-generator) library to create LaunchDarkly REST API client libraries from our [OpenAPI spec](https://app.launchdarkly.com/api/v2/openapi.json).

The LaunchDarkly REST API is for custom integrations, data export, or automating feature flag workflows. *DO NOT* use these libraries to add feature flags to web or mobile applications. To integrate feature flags with applications, please see the [SDK documentation](https://docs.launchdarkly.com/sdk).

## Code generation

Server/client code for the API can be automatically generated. To generate the code:

  1. Ensure that you have `wget` and `jq` installed.
  1. The default make command will generate all target libraries:
```
> make
```

## Publishing code changes to platform-specific code repositories

Publishing codes changes is done by setting up the source repos for each client code repo as git submodules of the
targets directory.  This is done by running `make load_prior_targets` to set up the git submodules.

Then `make` can be run to layer changes on top of the existing repos, followed by `make push` to push the changes to
those repos.

## Uploading packages

The target `make publish` will publish changes to the language-specific package managers.
