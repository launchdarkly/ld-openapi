# LaunchDarkly OpenAPI
This repository contains an OpenAPI specification for LaunchDarkly's REST API.

This REST API is for custom integrations, data export, or automating your feature flag workflows. *DO NOT* use this client library to add feature flags to your web or mobile application. To integrate feature flags with your application, please see the [SDK documentation](https://docs.launchdarkly.com/v2.0/docs)

## Directory architecture
This project uses JSON file pointers to create the directory architecture described here: 

http://azimi.me/2015/07/16/split-swagger-into-smaller-files.html

## Compiling the spec
It may be useful to compile the spec to a single file. To do so follow these instructions:

  1. Install dependencies:

        npm install

  2. Compile to a single yaml:

        npm run compile

Alternatively, you can test a multi-file Swagger spec using VSCode, or by following these instructions for the online editor: 

https://apihandyman.io/writing-openapi-swagger-specification-tutorial-part-8-splitting-specification-file/#editing-splitted-local-files-with-the-online-editor

## Suggested editors

- [VSCode Swagger Viewer extension](https://marketplace.visualstudio.com/items?itemName=Arjun.swagger-viewer) 
- [Swagger Web Editor](http://editor.swagger.io/)


## Code generation
Server/client code for the API can be automatically generated. To generate the code:

  1. Install `swagger-codegen`:

        brew install swagger-codegen

  2. Run the `generate` command:

        npm run generate
