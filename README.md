# LaunchDarkly OpenAPI

This repository contains an OpenAPI specification for LaunchDarkly's REST API.

This REST API is for custom integrations, data export, or automating your feature flag workflows. *DO NOT* use this client library to add feature flags to your web or mobile application. To integrate feature flags with your application, please see the [SDK documentation](https://docs.launchdarkly.com/v2.0/docs)

## Directory architecture

This project uses YAML file pointers to create the directory architecture described here: 

http://azimi.me/2015/07/16/split-swagger-into-smaller-files.html

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

## Publishing code changes to platform-specific code repositories

Publishing codes changes is done by setting up the source repos for each client code repo as git submodules of the
targets directory.  This is done by running `make load_prior_targets` to set up the git submodules.

Then `make` can be run to layer changes on top of the existing repos, followed by `make push` to push the changes to
those repos.

## Uploading packages

The target `make publish` will publish changes to the language-specific package managers.
