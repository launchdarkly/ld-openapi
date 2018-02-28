
SHELL = /bin/bash

VERSION = 1.0.2
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

TEMP_DIR := $(shell mktemp -d)

all: $(TARGETS)

$(TARGETS_PATH):
	mkdir -p $@

$(TARGETS): spec
	rm -rf $(TARGETS_PATH)/$(PREFIX)-$@
	mkdir -p $(TARGETS_PATH)/$(PREFIX)-$@
	cp $(TARGETS_PATH)/swagger.yaml $(TEMP_DIR)/swagger.yaml
	./scripts/preprocess-yaml-$@.sh $(TEMP_DIR)/swagger.yaml || true
	swagger-codegen generate `cat ./config/params-$@ || true` --artifact-version $(VERSION) -i $(TEMP_DIR)/swagger.yaml -l $@ -o $(TARGETS_PATH)/$(PREFIX)-$@
	cp ./LICENSE.txt $(TARGETS_PATH)/$(PREFIX)-$@/LICENSE.txt
	mv $(TARGETS_PATH)/$(PREFIX)-$@/README.md $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md || touch $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md
	cat ./README-PREFIX.md $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md > $(TARGETS_PATH)/$(PREFIX)-$@/README.md 
	rm $(TARGETS_PATH)/$(PREFIX)-$@/README-ORIGINAL.md

spec: $(TARGETS_PATH)
	./node_modules/.bin/multi-file-swagger ./index.yaml > $(TARGETS_PATH)/swagger.json
	./node_modules/.bin/multi-file-swagger -o yaml ./index.yaml > $(TARGETS_PATH)/swagger.yaml
	./node_modules/.bin/swagger validate $(TARGETS_PATH)/swagger.yaml

clean:
	rm -rf $(TARGETS_PATH)

.PHONY: $(TARGETS) all spec clean
