SHELL = /bin/bash

VERSION=$(shell cat $(TARGETS_PATH)/openapi.json | jq -r '.info.version' )
REVISION:=$(git rev-parse --short HEAD)

API_TARGETS = \
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

RELEASE_BRANCH ?= master                  # when we bump a major version, we may need to change this
PREV_RELEASE_BRANCH ?= $(RELEASE_BRANCH)  # override this to create a revision of an older branch
RELEASE_TARGETS ?= $(API_TARGETS)         # for now, we don't release the docs to repos
RELEASE_SUFFIX ?=                         # allows the private branch to push to repos with a "-private" suffix

REPO ?= ld-openapi$(RELEASE_SUFFIX)
REPO_USER_URL ?= https://github.com/launchdarkly

DOC_TARGETS = \
	html \
	html2

API_CLIENT_PREFIX = api-client

TARGETS_PATH ?= ./targets

LASTHASH := $(shell git rev-parse --short HEAD)

# The following variables define any special command-line parameters that need to be passed
# to swagger-codegen for each language/platform. In most cases these are undocumented and
# were discovered by looking in the swagger-codegen source.
CODEGEN_PARAMS_csharp_dotnet2 = -DpackageName=LaunchDarkly.Api -DclientPackage=LaunchDarkly.Api.Client
CODEGEN_PARAMS_go = -DpackageName=ldapi
CODEGEN_PARAMS_java = --group-id com.launchdarkly --artifact-id api-client --api-package com.launchdarkly.api.api --model-package com.launchdarkly.api.model
CODEGEN_PARAMS_python = -DpackageName=launchdarkly_api
CODEGEN_PARAMS_ruby = -DmoduleName=LaunchDarklyApi -DgemName=launchdarkly_api -DgemVersion=$(VERSION) -DgemHomepage=https://github.com/launchdarkly/api-client-ruby

TARGET_OPENAPI_YAML = $(TARGETS_PATH)/openapi.yaml
TARGET_OPENAPI_JSON = $(TARGETS_PATH)/openapi.json

MULTI_FILE_SWAGGER = node_modules/.bin/multi-file-swagger
CODEGEN = swagger-codegen

ifeq ($(OS),Darwin)
CODEGEN_INSTALL_MSG = "Run 'brew install swagger-codegen' to install swagger-codegen"
else
CODEGEN_INSTALL_MSG = "You must install swagger-codegen before building this target"
endif

all: $(API_TARGETS) $(DOC_TARGETS)

load_prior_targets:
	rm -rf $(TARGETS_PATH)
	mkdir -p $(TARGETS_PATH)
	set -e; \
	cd $(TARGETS_PATH); \
	git init; \
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
	 git submodule add -b $(PREV_RELEASE_BRANCH) $(REPO_USER_URL)/api-client-$(RELEASE_TARGETS)$(RELEASE_SUFFIX) ./api-client-$(RELEASE_TARGET)); \

openapi_yaml: $(TARGETS_PATH) $(MULTI_FILE_SWAGGER) $(CHECK_CODEGEN)
	$(MULTI_FILE_SWAGGER) openapi.yaml > $(TARGET_OPENAPI_JSON)
	$(MULTI_FILE_SWAGGER) -o yaml openapi.yaml > $(TARGET_OPENAPI_YAML)
	$(CODEGEN) validate -i $(TARGET_OPENAPI_YAML)

$(TARGETS_PATH):
	mkdir -p $@

$(API_TARGETS): openapi_yaml
	$(eval BUILD_DIR := $(TARGETS_PATH)/$(API_CLIENT_PREFIX)-$@)
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	if [ -e "./scripts/preprocess-yaml-$@.sh" ]; then \
		./scripts/preprocess-yaml-$@.sh $(TARGET_OPENAPI_YAML) > $(BUILD_DIR)/openapi.yml; \
	else \
		cat $(TARGET_OPENAPI_YAML) > $(BUILD_DIR)/openapi.yml; \
	fi
	$(CODEGEN) generate -i $(BUILD_DIR)/openapi.yml $(CODEGEN_PARAMS_$@) -l $@ --artifact-version $(VERSION) -o $(BUILD_DIR)
	cp ./LICENSE.txt $(BUILD_DIR)/LICENSE.txt
	mv $(BUILD_DIR)/README.md $(BUILD_DIR)/README-ORIGINAL.md || touch $(BUILD_DIR)/README-ORIGINAL.md
	cat ./README-PREFIX.md $(BUILD_DIR)/README-ORIGINAL.md > $(BUILD_DIR)/README.md
	rm $(BUILD_DIR)/README-ORIGINAL.md

$(DOC_TARGETS): openapi_yaml
	$(eval BUILD_DIR := $(TARGETS_PATH)/$@)
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	$(CODEGEN) generate -i $(TARGET_OPENAPI_YAML) $(CODEGEN_PARAMS_$@) -l $@ --artifact-version $(VERSION) -o $(BUILD_DIR)

$(MULTI_FILE_SWAGGER):
	yarn add --no-lockfile multi-file-swagger

GIT_COMMAND=git
GIT_PUSH_COMMAND=git push

push_test: GIT_COMMAND=echo git
push_test: push

push_dry_run: GIT_PUSH_COMMAND=git push --dry-run
push:
	$(GIT_COMMAND) submodule foreach git add .; \
	$(GIT_COMMAND) submodule foreach git commit --allow-empty -m "Version $(VERSION) automatically generated from $(REPO)@$(REVISION)."; \
	$(GIT_COMMAND) submodule foreach git tag $(VERSION); \
	$(GIT_COMMAND) submodule foreach $(GIT_PUSH_COMMAND) --follow-tags origin $(RELEASE_BRANCH)

publish:
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
		[ ! -f ./scripts/release/$(RELEASE_TARGET).sh ] || ./scripts/release/$(RELEASE_TARGET).sh targets/api-client-$(RELEASE_TARGET) $(RELEASE_TARGET); \
	)

check_codegen:
	command $(CODEGEN) > /dev/null 2>&1 || { echo $CODEGEN_INSTALL_MSG; false; }

clean:
	rm -rf $(TARGETS_PATH)

.PHONY: $(TARGETS) all check_codegen clean load_prior_targets openapi_yaml push push_dry_run push_test
