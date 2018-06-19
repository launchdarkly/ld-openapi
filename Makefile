
SHELL = /bin/bash

VERSION=$(shell cat targets/swagger.json | jq -r '.info.version' )
TARGETS = \
	bash \
	go \
	csharp-dotnet2 \
	java \
	python \
	javascript \
	nodejs-server \
	typescript-node \
	php \
	ruby \
	rails5

PREFIX = api-client

TARGETS_PATH ?= ./targets
LASTHASH := $(shell git rev-parse --short HEAD)

# The following variables define any special command-line parameters that need to be passed
# to swagger-codegen for each language/platform. In most cases these are undocumented and
# were discovered by looking in the swagger-codegen source.
CODEGEN_PARAMS_csharp_dotnet2 := -DpackageName=LaunchDarkly.Api -DclientPackage=LaunchDarkly.Api.Client
CODEGEN_PARAMS_go := -DpackageName=ldapi
CODEGEN_PARAMS_java := --group-id com.launchdarkly --artifact-id api-client --api-package com.launchdarkly.api.api --model-package com.launchdarkly.api.model
CODEGEN_PARAMS_python := -DpackageName=launchdarkly_api
CODEGEN_PARAMS_ruby := -DmoduleName=LaunchDarklyApi -DgemName=launchdarkly_api -DgemVersion=$(VERSION) -DgemHomepage=https://github.com/launchdarkly/api-client-ruby

all: $(TARGETS)

$(TARGETS_PATH):
	mkdir -p $@

$(TARGETS): spec
	$(eval TEMP_DIR := $(shell mktemp -d))
	rm -rf $(TARGETS_PATH)/$(PREFIX)-$@
	mkdir -p $(TARGETS_PATH)/$(PREFIX)-$@
	cp $(TARGETS_PATH)/swagger.yaml $(TEMP_DIR)/swagger.yaml
	if [ -e "./scripts/preprocess-yaml-$@.sh" ]; then ./scripts/preprocess-yaml-$@.sh $(TEMP_DIR)/swagger.yaml; fi
	swagger-codegen generate $(CODEGEN_PARAMS_$@) --artifact-version $(VERSION) -i $(TEMP_DIR)/swagger.yaml -l $@ -o $(TARGETS_PATH)/$(PREFIX)-$@
	cp ./LICENSE.txt $(TARGETS_PATH)/$(PREFIX)-$@/LICENSE.txt
	mv $(TARGETS_PATH)/$(PREFIX)-$@/README.md $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md || touch $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md
	cat ./README-PREFIX.md $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md > $(TARGETS_PATH)/$(PREFIX)-$@/README.md 
	rm $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md
	rm -rf $(TEMP_DIR)

spec: $(TARGETS_PATH)
	./node_modules/.bin/multi-file-swagger ./index.yaml > $(TARGETS_PATH)/swagger.json
	./node_modules/.bin/multi-file-swagger -o yaml ./index.yaml > $(TARGETS_PATH)/swagger.yaml
	./node_modules/.bin/swagger validate $(TARGETS_PATH)/swagger.yaml

clean:
	rm -rf $(TARGETS_PATH)

.PHONY: $(TARGETS) all spec clean
