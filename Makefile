SHELL = /bin/bash

LD_RELEASE_VERSION ?= 0.0.1-SNAPSHOT

GENERATOR_VERSION=6.0.0
GENERATOR_JAR=openapi-generator-cli-${GENERATOR_VERSION}.jar
GENERATOR_DOWNLOAD_URL=https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/${GENERATOR_VERSION}/${GENERATOR_JAR}

OPENAPI_JSON_URL=https://app.launchdarkly.com/api/v2/openapi.json

API_TARGETS ?= \
	go \
	java \
	javascript \
	php \
	python \
	ruby \
	typescript-axios

RELEASE_BRANCH ?= main                  # when we bump a major version, we may need to change this
PREV_RELEASE_BRANCH ?= $(RELEASE_BRANCH)  # override this to create a revision of an older branch
RELEASE_TARGETS ?= $(API_TARGETS)         # for now, we don't release the docs to repos
RELEASE_SUFFIX ?=                         # allows the private branch to push to repos with a "-private" suffix

PUBLISH_TARGETS ?= $(RELEASE_TARGETS)

REPO ?= ld-openapi$(RELEASE_SUFFIX)
REPO_USER_URL ?= https://github.com/launchdarkly
TAG ?= $(LD_RELEASE_VERSION)

DOC_TARGETS = \
	html \
	html2

API_CLIENT_PREFIX = api-client

TARGETS_PATH ?= ./targets
CLIENT_CLONES_PATH ?= ./client-clones
TEMPLATES_PATH ?= ./swagger-codegen-templates
SAMPLES_PATH ?= ./samples

# The following variables define any special command-line parameters that need to be passed
# to openapi-generator for each language/platform.
CODEGEN_PARAMS_go = --additional-properties=packageName=ldapi \
	--additional-properties=email=support@launchdarkly.com \
	--additional-properties=developerName=LaunchDarkly \
	--additional-properties=developerEmail=support@launchdarkly.com \
	--additional-properties=developerOrganization=LaunchDarkly \
	--additional-properties=developerOrganizationUrl=https://launchdarkly.com \
	--additional-properties=packageVersion=$(firstword $(subst ., ,$(TAG))) \
	-t $(TEMPLATES_PATH)/go
CODEGEN_PARAMS_java = \
	-t $(TEMPLATES_PATH)/java \
	--group-id com.launchdarkly \
	--api-package com.launchdarkly.api.api \
	--model-package com.launchdarkly.api.model \
	--additional-properties=disallowAdditionalPropertiesIfNotPresent=false \
	--additional-properties=artifactId=api-client \
	--additional-properties=email=support@launchdarkly.com \
	--additional-properties=developerName=LaunchDarkly \
	--additional-properties=developerEmail=support@launchdarkly.com \
	--additional-properties=developerOrganization=LaunchDarkly \
	--additional-properties=developerOrganizationUrl=https://launchdarkly.com \
	--additional-properties=artifactUrl=https://github.com/launchdarkly/api-client-java \
	--additional-properties=artifactDescription="Build custom integrations with the LaunchDarkly REST API" \
	--additional-properties=scmUrl="https://github.com/launchdarkly/api-client-java" \
	--additional-properties=scmConnection='scm:git:git://github.com/launchdarkly/api-client-java.git' \
	--additional-properties=scmDeveloperConnection='scm:git:ssh:git@github.com:launchdarkly/api-client-java.git'
CODEGEN_PARAMS_javascript = \
	-t $(TEMPLATES_PATH)/javascript \
	--additional-properties=projectName=launchdarkly-api \
	--additional-properties=projectVersion=$(TAG) \
	--additional-properties=projectDescription="Build custom integrations with the LaunchDarkly REST API" \
	--additional-properties=moduleName=LaunchDarklyApi
CODEGEN_PARAMS_php = \
	--additional-properties=packagePath=LaunchDarklyApi \
	--additional-properties=composerVendorName=launchdarkly \
	--additional-properties=composerProjectName=api-client-php \
	--additional-properties=invokerPackage=LaunchDarklyApi \
	--git-user-id=launchdarkly \
	--git-repo-id=api-client-php
CODEGEN_PARAMS_python = \
	-t $(TEMPLATES_PATH)/python \
	--additional-properties=packageName=launchdarkly_api \
	--additional-properties=packageVersion=$(TAG) \

CODEGEN_PARAMS_typescript-axios = \
	-t $(TEMPLATES_PATH)/typescript-axios \
	--additional-properties=npmName=launchdarkly-api-typescript \
	--additional-properties=npmVersion=$(TAG) \
	--additional-properties=supportsES6=true
CODEGEN_PARAMS_ruby = \
  --additional-properties=moduleName=LaunchDarklyApi \
  --additional-properties=gemName=launchdarkly_api \
  --additional-properties=gemVersion=$(TAG) \

SAMPLE_FILE_go = main.go
SAMPLE_FILE_javascript = index.js
SAMPLE_FILE_python = main.py
SAMPLE_FILE_ruby = main.rb
SAMPLE_FILE_typescript-axios = index.ts

SAMPLE_FORMAT_go = go
SAMPLE_FORMAT_javascript = js
SAMPLE_FORMAT_python = python
SAMPLE_FORMAT_ruby = ruby
SAMPLE_FORMAT_typescript-axios = ts

TARGET_OPENAPI_JSON = $(TARGETS_PATH)/openapi.json

CODEGEN = exec java -jar ${GENERATOR_JAR}

all: $(API_TARGETS) $(DOC_TARGETS)

load_prior_targets:
	rm -rf $(TARGETS_PATH)
	mkdir -p $(TARGETS_PATH)
	set -e
	cd $(TARGETS_PATH)
	git init
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
	 git submodule add $(REPO_USER_URL)/api-client-$(RELEASE_TARGET)$(RELEASE_SUFFIX) ./api-client-$(RELEASE_TARGET) && git checkout $(PREV_RELEASE_BRANCH) ;)

$(GENERATOR_JAR):
	curl -s -L --fail ${GENERATOR_DOWNLOAD_URL} > $@

$(TARGET_OPENAPI_JSON): $(GENERATOR_JAR) $(TARGETS_PATH)
	curl -s -L --fail $(OPENAPI_JSON_URL) > $@

$(TARGETS_PATH):
	mkdir -p $@

$(API_TARGETS): $(TARGET_OPENAPI_JSON)
	$(eval BUILD_DIR := $(TARGETS_PATH)/$(API_CLIENT_PREFIX)-$@)
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	$(CODEGEN) generate -i $(TARGET_OPENAPI_JSON) $(CODEGEN_PARAMS_$@) -g $@ --additional-properties=artifactVersion=$(LD_RELEASE_VERSION) --git-host=github.com --git-user-id=launchdarkly --git-repo-id=api-client-$@ -o $(BUILD_DIR)
	cp ./LICENSE.txt $(BUILD_DIR)/LICENSE.txt
	mv $(BUILD_DIR)/README.md $(BUILD_DIR)/README-ORIGINAL.md || touch $(BUILD_DIR)/README-ORIGINAL.md
	if [ -f "$(SAMPLES_PATH)/$@/$(SAMPLE_FILE_$@)" ]; then \
		cat ./README-PREFIX.md > $(BUILD_DIR)/README.md; \
		echo -e "View our [sample code](#sample-code) for example usage.\n" >> $(BUILD_DIR)/README.md; \
		cat $(BUILD_DIR)/README-ORIGINAL.md >> $(BUILD_DIR)/README.md; \
		echo -e "## Sample Code\n" >> $(BUILD_DIR)/README.md; \
		echo '```${SAMPLE_FORMAT_$@}' >> $(BUILD_DIR)/README.md; \
		cat $(SAMPLES_PATH)/$@/$(SAMPLE_FILE_$@) >> $(BUILD_DIR)/README.md; \
		echo '```' >> $(BUILD_DIR)/README.md; \
	else \
		cat ./README-PREFIX.md $(BUILD_DIR)/README-ORIGINAL.md > $(BUILD_DIR)/README.md; \
	fi
	rm $(BUILD_DIR)/README-ORIGINAL.md

# Generates all API targets using Docker
targets_docker:
	docker run -ti -v `pwd`:/workspace -e LD_RELEASE_VERSION --workdir /workspace \
	  ldcircleci/openapi-release:1 make all

$(DOC_TARGETS):
	$(eval BUILD_DIR := $(TARGETS_PATH)/$@)
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	$(CODEGEN) generate -i $(TARGET_OPENAPI_JSON) $(CODEGEN_PARAMS_$@) -g $@ --artifact-version $(LD_RELEASE_VERSION) -o $(BUILD_DIR)

GIT_COMMAND=git
GIT_PUSH_COMMAND=git push
GIT_PUSH_DESC=Publishing updates

push_test: GIT_COMMAND=echo git
push_test: push

push_dry_run: GIT_PUSH_COMMAND=git push --dry-run
push_dry_run: GIT_PUSH_DESC=Simulating the updates we would do
# for each client library, clone the repository and replace the contents with the newly generated client
push:
	mkdir $(CLIENT_CLONES_PATH); \
	cd $(CLIENT_CLONES_PATH); \
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
		echo $(GIT_PUSH_DESC) to the $(RELEASE_TARGET) client repository...; \
		$(GIT_COMMAND) clone https://github.com/launchdarkly/api-client-$(RELEASE_TARGET).git || exit 1; \
		rm -r api-client-$(RELEASE_TARGET)/*; \
		cp -v -r ../$(TARGETS_PATH)/api-client-$(RELEASE_TARGET) .; \
		cd api-client-$(RELEASE_TARGET); \
		$(GIT_COMMAND) add .; \
		$(GIT_COMMAND) status; \
		$(GIT_COMMAND) commit --allow-empty -m "Version $(LD_RELEASE_VERSION) automatically generated from $(REPO)."; \
		$(GIT_COMMAND) tag $(TAG); \
		$(GIT_PUSH_COMMAND) origin $(TAG); \
		$(GIT_PUSH_COMMAND) origin $(RELEASE_BRANCH); \
		if [ $(RELEASE_TARGET) == "go" ]; then \
		  $(GIT_COMMAND) tag v$(TAG); \
		  $(GIT_PUSH_COMMAND) origin v$(TAG); \
		fi; \
		cd ..; \
	) \

build_clients:
	./scripts/run-scripts-for-targets.sh ./scripts/build $(VERSION) \
		"Building client code" $(BUILD_TARGETS)

publish:
	./scripts/run-scripts-for-targets.sh ./scripts/release $(LD_RELEASE_VERSION) \
		"Publishing client artifacts" $(PUBLISH_TARGETS)

publish_dry_run:
	./scripts/run-scripts-for-targets.sh ./scripts/release-dry-run $(LD_RELEASE_VERSION) \
		"Dry run simulation of publishing client artifacts" $(PUBLISH_TARGETS)

clean:
	rm -rf $(TARGETS_PATH)
	rm -rf $(CLIENT_CLONES_PATH)

.PHONY: $(TARGETS) all build_clients clean load_prior_targets push push_dry_run push_test targets_docker
