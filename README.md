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

This project is set up (via the files in `.ldrelease`) to work with LaunchDarkly's internal Releaser tool. Running a release via Releaser will execute the required `make` targets in the right order, sandboxed in a Docker container that contains all the necessary build tools. You can also do a "dry run" in Releaser, which does all of the _build_ steps and provides you with the build products, but does not push anything to GitHub or to package managers.

That is the preferred way of doing releases, but the `make` targets can also be run locally if necessary, as long as your local environment has all of the necessary tools installed (as defined by the Docker image selected in `.ldrelease/config.yml` and anything else that's installed in `.ldrelease/prepare.sh`). Here are more details about what they do:

* `make load_prior_targets`: Sets up the source repos for each client repository (such as `api-client-go`) as git submodules of the `targets` directory.
* `make all`: Generates the API spec, runs the OpenAPI code generator to create the code for each API client, and copies the generated code into the submodules in `targets`.
* `make build_clients`: Verifies that the generated code for each client can actually be built as a package. This runs the script for each client that is in `scripts/build`.
* `make push`: Pushes the changes in the submodules to the client repositories.
* `make push_dry_run`: Simulates what the result of `make push` would be.
* `make publish`: Pushes the client code to package managers, for platforms where this is applicable (such as NPM for the JavaScript clients). This runs the script for each client that is in `scripts/release`, if any.
* `make publish_dry_run`: Simulates what the result of `make publish` would be.This runs the script for each client that is in `scripts/build`, if any.

Or, if you just want to look at the generated code locally, run `make targets_docker` which is equivalent to `make all` but uses a Docker container, so that the only tool you need to have installed locally is Docker. The output will appear in `./targets`. This is a convenient way to validate any local changes that relate to code generation. If you are also making changes that affect how the client code is packaged or published, it is better to use the slower but more comprehensive method of a Releaser dry run.

When running any `make` targets locally, set the environment variable `$LD_RELEASE_VERSION` to the version you are releasing, such as "6.0.0". It is set automatically when releases are run through Releaser.

