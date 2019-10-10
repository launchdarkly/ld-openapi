# LaunchDarkly OpenAPI

This repository contains an OpenAPI specification for LaunchDarkly's REST API.

This REST API is for custom integrations, data export, or automating your feature flag workflows. *DO NOT* use this client library to add feature flags to your web or mobile application. To integrate feature flags with your application, please see the [SDK documentation](https://docs.launchdarkly.com/v2.0/docs)

## Directory architecture

This project uses YAML file pointers to create the directory architecture described here: 

http://azimi.me/2015/07/16/split-swagger-into-smaller-files.html

## Compiling the spec

The spec is joined from multiple files using a multi-file Swagger tool.  To compile the just spec run `make openapi_yaml`.

Alternatively, you can test a multi-file Swagger spec using VSCode, or by following these instructions for the online editor: 

https://apihandyman.io/writing-openapi-swagger-specification-tutorial-part-8-splitting-specification-file/#editing-splitted-local-files-with-the-online-editor

## Testing the spec

We use the spec to build some internals tools in go.  Tests for other specs are forthcoming.

## Suggested editors

- [VSCode Swagger Viewer extension](https://marketplace.visualstudio.com/items?itemName=Arjun.swagger-viewer) 
- [Swagger Web Editor](http://editor.swagger.io/)

## Code generation

Server/client code for the API can be automatically generated. To generate the code:

  1. Ensure that you have `wget`, `yarn`, and `jq` installed. 
  1. Run the `generate` command:
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

## Automatic releases on CircleCI

On CircleCI, builds tagged with `#.#.#[optional suffix]` (e.g. 2.0.1 or 2.0.3-test) will trigger the publishing job
that will push new code and upload new packages.  For private development, we use a private version of this repository
and we do not publish things like npm packages for the private repo.  This job will also create a release on GitHub
for the current repo, containing the openapi specs and an archive of the generated code.
