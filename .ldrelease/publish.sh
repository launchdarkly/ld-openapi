#!/usr/bin/env bash

set -eu

# Configure GitHub access token for pushing to client repositories
# (We're not doing this in prepare.sh because we want to make sure there's no way the
# build/test scripts can accidentally push to GitHub)
echo >>~/.netrc "machine github.com login LaunchDarklyReleaseBot password $(cat $LD_RELEASE_SECRETS_DIR/github_token)"
git config --global user.name LaunchDarklyReleaseBot
git config --global user.email launchdarklyreleasebot@launchdarkly.com

# Publish updates to client repositories
echo Publishing updates to client repositories...
make RELEASE_TARGETS="java" TAG=${LD_RELEASE_VERSION} push

# Publish client artifacts to registries
echo Publishing client artifacts to registries...
make PUBLISH_TARGETS="java" publish
