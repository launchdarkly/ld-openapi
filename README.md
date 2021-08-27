# LaunchDarkly OpenAPI

This repository contains an OpenAPI specification for LaunchDarkly's REST API.

This REST API is for custom integrations, data export, or automating your feature flag workflows. *DO NOT* use this client library to add feature flags to your web or mobile application. To integrate feature flags with your application, please see the [SDK documentation](https://docs.launchdarkly.com/v2.0/docs)

## Directory architecture

This project uses YAML file pointers to create the directory architecture described here: 

http://azimi.me/2015/07/16/split-swagger-into-smaller-files.html

## Compiling the spec

The spec is joined from multiple files using a multi-file Swagger tool.  To compile just the spec run `make openapi_yaml`.

Alternatively, you can test a multi-file Swagger spec using VSCode, or by following these instructions for the online editor: 

https://apihandyman.io/writing-openapi-swagger-specification-tutorial-part-8-splitting-specification-file/#editing-splitted-local-files-with-the-online-editor

## Testing the spec

We use the spec to build some internals tools in go.  Tests for other specs are forthcoming.

## Suggested editors

- [VSCode Swagger Viewer extension](https://marketplace.visualstudio.com/items?itemName=Arjun.swagger-viewer) 
- [Swagger Web Editor](http://editor.swagger.io/)

## Code generation

Server/client code for the API can be automatically generated. To generate the code:

  1. Ensure that you have `wget`, `yarn`, `jq`, and `pip3` installed. 
  1. Run the `generate` command:
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
