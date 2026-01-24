# LaunchDarkly OpenAPI

This repository uses the [OpenAPI Generator](https://github.com/OpenAPITools/openapi-generator) library to create LaunchDarkly REST API client libraries from our [OpenAPI spec](https://app.launchdarkly.com/api/v2/openapi.json).

The LaunchDarkly REST API is for custom integrations, data export, or automating feature flag workflows. *DO NOT* use these libraries to add feature flags to web or mobile applications. To integrate feature flags with applications, please see the [SDK documentation](https://docs.launchdarkly.com/sdk).

## Code generation

Server/client code for the API can be automatically generated. To generate the code:

  1. Ensure that you have `curl` and `jq` installed.
  1. The default make command will generate all target libraries:
```
> make
```

## How releases work

This project is set up to use [Github Actions](https://github.com/launchdarkly/ld-openapi-private/actions/workflows/release.yml) to release new versions.