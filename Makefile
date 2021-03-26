SHELL = /bin/bash

VERSION=$(shell cat $(TARGETS_PATH)/openapi.json | jq -r '.info.version' )
REVISION:=$(shell git rev-parse --short HEAD)

SWAGGER_VERSION=3.0.24
SWAGGER_JAR=swagger-codegen-cli-${SWAGGER_VERSION}.jar
SWAGGER_DOWNLOAD_URL=https://repo1.maven.org/maven2/io/swagger/codegen/v3/swagger-codegen-cli/${SWAGGER_VERSION}/${SWAGGER_JAR}
OPENAPI_JSON_URL=https://ld-stg.launchdarkly.com/api/v2/openapi.json

API_TARGETS ?= \
	csharp-dotnet2 \
	go \
	java \
	javascript \
	php \
	python \
	ruby \
	typescript-axios

RELEASE_BRANCH ?= master                  # when we bump a major version, we may need to change this
PREV_RELEASE_BRANCH ?= $(RELEASE_BRANCH)  # override this to create a revision of an older branch
RELEASE_TARGETS ?= $(API_TARGETS)         # for now, we don't release the docs to repos
RELEASE_SUFFIX ?=                         # allows the private branch to push to repos with a "-private" suffix

PUBLISH_TARGETS ?= $(RELEASE_TARGETS)

REPO ?= ld-openapi$(RELEASE_SUFFIX)
REPO_USER_URL ?= https://github.com/launchdarkly
TAG ?= $(VERSION)

DOC_TARGETS = \
	html \
	html2

API_CLIENT_PREFIX = api-client

TARGETS_PATH ?= ./targets
CLIENT_CLONES_PATH ?= ./client-clones
TEMPLATES_PATH ?= ./swagger-codegen-templates
SAMPLES_PATH ?= ./samples

LASTHASH := $(shell git rev-parse --short HEAD)

# The following variables define any special command-line parameters that need to be passed
# to swagger-codegen for each language/platform. In most cases these are undocumented and
# were discovered by looking in the swagger-codegen source.
CODEGEN_PARAMS_csharp-dotnet2 = -DpackageName=LaunchDarkly.Api -DclientPackage=LaunchDarkly.Api.Client
CODEGEN_PARAMS_go = -DpackageName=ldapi -t $(TEMPLATES_PATH)/go
CODEGEN_PARAMS_java = \
	--group-id com.launchdarkly \
	--api-package com.launchdarkly.api.api \
	--model-package com.launchdarkly.api.model \
	-DartifactId=api-client \
	-Demail=support@launchdarkly.com \
	-DdeveloperName=LaunchDarkly \
	-DdeveloperEmail=support@launchdarkly.com \
	-DdeveloperOrganization=LaunchDarkly \
	-DdeveloperOrganizationUrl=https://launchdarkly.com \
	-DartifactUrl=https://github.com/launchdarkly/api-client-java \
	-DartifactDescription="Build custom integrations with the LaunchDarkly REST API" \
	-DscmUrl="https://github.com/launchdarkly/api-client-java" \
	-DscmConnection='scm:git:git://github.com/launchdarkly/api-client-java.git' \
	-DscmDeveloperConnection='scm:git:ssh:git@github.com:launchdarkly/api-client-java.git'
CODEGEN_PARAMS_javascript = \
	-t $(TEMPLATES_PATH)/javascript \
	-DprojectName=launchdarkly-api \
	-DprojectDescription="Build custom integrations with the LaunchDarkly REST API" \
	-DmoduleName=LaunchDarklyApi
CODEGEN_PARAMS_php = \
	-DpackagePath=LaunchDarklyApi \
	-DcomposerVendorName=launchdarkly \
	-DcomposerProjectName=api-client-php \
	-DinvokerPackage=LaunchDarklyApi \
	-DgitUserId=launchdarkly \
	-DgitRepoId=api-client-php
CODEGEN_PARAMS_python = -DpackageName=launchdarkly_api -DpackageVersion=$(TAG)
CODEGEN_PARAMS_typescript-node = \
	-t $(TEMPLATES_PATH)/typescript-node \
	-DnpmName=launchdarkly-api-typescript \
	-DnpmVersion=$(TAG) \
	-DsupportsES6=true
CODEGEN_PARAMS_ruby = \
  -t $(TEMPLATES_PATH)/ruby \
  -DmoduleName=LaunchDarklyApi \
  -DgemName=launchdarkly_api \
  -DgemVersion=$(TAG) \
  -DgemHomepage=https://github.com/launchdarkly/api-client-ruby \
  -DgemAuthor=LaunchDarkly \
  -DgemAuthorEmail=support@launchdarkly.com

SAMPLE_FILE_go = main.go
SAMPLE_FILE_javascript = index.js
SAMPLE_FILE_python = main.py
SAMPLE_FILE_ruby = main.rb
SAMPLE_FILE_typescript-node = index.ts

SAMPLE_FORMAT_go = go
SAMPLE_FORMAT_javascript = js
SAMPLE_FORMAT_python = python
SAMPLE_FORMAT_ruby = ruby
SAMPLE_FORMAT_typescript-node = ts

TARGET_OPENAPI_YAML = $(TARGETS_PATH)/openapi.yaml
TARGET_OPENAPI_JSON = $(TARGETS_PATH)/openapi.json

CODEGEN = exec java -jar ${SWAGGER_JAR}

all: $(API_TARGETS) $(DOC_TARGETS) gh-pages

load_prior_targets:
	rm -rf $(TARGETS_PATH)
	mkdir -p $(TARGETS_PATH)
	set -e; \
	cd $(TARGETS_PATH); \
	git init; \
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
	 git submodule add -b $(PREV_RELEASE_BRANCH) $(REPO_USER_URL)/api-client-$(RELEASE_TARGET)$(RELEASE_SUFFIX) ./api-client-$(RELEASE_TARGET) ;) \
	git submodule add -b gh-pages $(REPO_USER_URL)/ld-openapi$(RELEASE_SUFFIX) gh-pages

$(TARGET_OPENAPI_JSON):
	wget $(OPENAPI_JSON_URL) -O $(TARGET_OPENAPI_JSON)

openapi_yaml: $(SWAGGER_JAR) $(TARGETS_PATH) $(CHECK_CODEGEN) $(TARGET_OPENAPI_JSON)
	$(CODEGEN) generate -i $(TARGET_OPENAPI_JSON) -l openapi-yaml -o $(TARGETS_PATH)

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
	if [ -f "$(SAMPLES_PATH)/$@/$(SAMPLE_FILE_$@)" ]; then \
		echo -e "## Sample Code\n" >> $(BUILD_DIR)/README.md; \
		echo '```${SAMPLE_FORMAT_$@}' >> $(BUILD_DIR)/README.md; \
		cat $(SAMPLES_PATH)/$@/$(SAMPLE_FILE_$@) >> $(BUILD_DIR)/README.md; \
		echo '```' >> $(BUILD_DIR)/README.md; \
	fi
	rm $(BUILD_DIR)/README-ORIGINAL.md

# Generates openapi.yaml using Docker
openapi_yaml_docker:
	docker build . -t ld-openapi && docker run -ti -v `pwd`:/workspace ld-openapi:latest make openapi_yaml

# Generates all API targets using Docker
targets_docker:
	docker build . -t ld-openapi && docker run -ti -v `pwd`:/workspace ld-openapi:latest make

$(DOC_TARGETS): openapi_yaml
	$(eval BUILD_DIR := $(TARGETS_PATH)/$@)
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	$(CODEGEN) generate -i $(TARGET_OPENAPI_YAML) $(CODEGEN_PARAMS_$@) -l $@ --artifact-version $(VERSION) -o $(BUILD_DIR)

gh-pages: openapi_yaml
	mkdir -p targets/gh-pages
	cp $(TARGET_OPENAPI_JSON) $(TARGETS_PATH)/gh-pages/
	cp $(TARGET_OPENAPI_YAML) $(TARGETS_PATH)/gh-pages/
	cp gh-pages/* $(TARGETS_PATH)/gh-pages/

GIT_COMMAND=git
GIT_PUSH_COMMAND=git push

push_test: GIT_COMMAND=echo git
push_test: push

push_dry_run: GIT_PUSH_COMMAND=git push --dry-run
push:
	mkdir $(CLIENT_CLONES_PATH); \
	cd $(CLIENT_CLONES_PATH); \
	$(foreach RELEASE_TARGET, $(RELEASE_TARGETS), \
		echo Publishing updates to the $(RELEASE_TARGET) client repository...; \
		$(GIT_COMMAND) clone git@github.com:launchdarkly/api-client-$(RELEASE_TARGET).git; \
		cp -v -r ../$(TARGETS_PATH)/api-client-$(RELEASE_TARGET) .; \
		cd api-client-$(RELEASE_TARGET); \
		$(GIT_COMMAND) add .; \
		$(GIT_COMMAND) status; \
		$(GIT_COMMAND) commit --allow-empty -m "Version $(VERSION) automatically generated from $(REPO)@$(REVISION)."; \
		$(GIT_COMMAND) tag $(TAG); \
		$(GIT_PUSH_COMMAND) origin $(TAG); \
		$(GIT_PUSH_COMMAND) origin $(RELEASE_BRANCH); \
		if [ $(RELEASE_TARGET) == "go" ]; then \
		  $(GIT_COMMAND) tag v$(TAG); \
		  $(GIT_PUSH_COMMAND) origin v$(TAG); \
		fi; \
		cd ..; \
	) \
	if [ $(PREV_RELEASE_BRANCH) == "master" ]; then \
		echo Publishing updates to GitHub pages...; \
		$(GIT_COMMAND) clone git@github.com:launchdarkly/$(REPO).git; \
		cd $(REPO); \
		$(GIT_COMMAND) checkout gh-pages --; \
		cp -v -r ../../$(TARGETS_PATH)/gh-pages/. .; \
		$(GIT_COMMAND) add .; \
		$(GIT_COMMAND) commit --allow-empty -m "Version $(VERSION) automatically generated from $(REPO)@$(REVISION)."; \
		$(GIT_PUSH_COMMAND) origin gh-pages; \
		cd ..; \
	fi

publish:
	$(foreach TARGET, $(PUBLISH_TARGETS), \
	    echo Publishing client artifacts for $(TARGET)...; \
		[ ! -f ./scripts/release/$(TARGET).sh ] || ./scripts/release/$(TARGET).sh targets/api-client-$(TARGET) $(TARGET) $(VERSION); \
	)

$(SWAGGER_JAR):
	wget ${SWAGGER_DOWNLOAD_URL} -O $@

clean:
	rm -rf $(TARGETS_PATH)
	rm -rf $(CLIENT_CLONES_PATH)

.PHONY: $(TARGETS) all clean gh-pages load_prior_targets openapi_yaml push push_dry_run push_test
