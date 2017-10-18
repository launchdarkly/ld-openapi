# LaunchDarkly OpenAPI
This repository contains an OpenAPI specification for LaunchDarkly's REST API.

## Editors
- [VSCode Swagger Viewer extension](https://marketplace.visualstudio.com/items?itemName=Arjun.swagger-viewer) 
- [Swagger Web Editor](http://editor.swagger.io/)


## Code generation
Server/client code for the API can be automatically generated. Procedure:

First, install codegen:
```bash
  brew install swagger-codegen
```

Then run generate
```bash
  npm run generate
```

## Directory architecture
This project uses JSON file pointers to create the directory architecture described here: http://azimi.me/2015/07/16/split-swagger-into-smaller-files.html

### Compile to single file
Compiling to a single file can be useful if you'd like to use the online editor. To do so follow these instructions:

  1. Install dependencies:

        npm install

  2. Compile to a single yaml:

        npm run compile

Alternatively, you can test a multi-file Swagger spec using VSCode, or by following these instructions for the online editor: https://apihandyman.io/writing-openapi-swagger-specification-tutorial-part-8-splitting-specification-file/#editing-splitted-local-files-with-the-online-editor