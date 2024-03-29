#!/usr/bin/env bash

set -eu

# Publish updates to client repositories
echo Dry run of updates to client repositories...
make TAG=${LD_RELEASE_VERSION} push_dry_run

# Publish client artifacts to registries
echo Dry run of publishing client artifacts to registries...
make PUBLISH_TARGETS="javascript python ruby typescript-axios java" publish_dry_run
