#!/usr/bin/env bash

set -eu

# Configure GitHub access token for pushing to client repositories
# (We're not doing this in prepare.sh because we want to make sure there's no way the
# build/test scripts can accidentally push to GitHub)
echo >>~/.netrc "machine github.com login LaunchDarklyReleaseBot password ${GH_TOKEN}"
git config --global user.name LaunchDarklyReleaseBot
git config --global user.email launchdarklyreleasebot@launchdarkly.com

if [ "${DRY_RUN:-false}" = "true" ]; then
  # Rehearsal: clones and commits for real, but pushes nothing and publishes nothing.
  echo Simulating updates to client repositories...
  make RELEASE_TARGETS="go java python ruby typescript-axios" TAG=${LD_RELEASE_VERSION} push_dry_run

  echo Simulating publishing of client artifacts...
  make PUBLISH_TARGETS="python ruby typescript-axios java" publish_dry_run
  exit 0
fi

# Publish updates to client repositories
echo Publishing updates to client repositories...
make RELEASE_TARGETS="go java python ruby typescript-axios" TAG=${LD_RELEASE_VERSION} push

# Publish client artifacts to registries
echo Publishing client artifacts to registries...
make PUBLISH_TARGETS="python ruby typescript-axios java" publish
