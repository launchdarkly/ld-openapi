#!/usr/bin/env bash

set -eu

# Configure GitHub access token for pushing to client repositories
# (We're not doing this in prepare.sh because we want to make sure there's no way the
# build/test scripts can accidentally push to GitHub)
echo >>~/.netrc "machine github.com login LaunchDarklyReleaseBot password ${GH_TOKEN}"
git config --global user.name LaunchDarklyReleaseBot
git config --global user.email launchdarklyreleasebot@launchdarkly.com

# Publish updates to client repositories
echo Publishing updates to client repositories...
make RELEASE_TARGETS="go java javascript php python ruby typescript-axios" TAG=${LD_RELEASE_VERSION} push

# Publish client artifacts to registries
echo Publishing client artifacts to registries...
make PUBLISH_TARGETS="javascript python ruby typescript-axios java" publish
