#!/usr/bin/env bash

set -eu

# Get host key for github
echo Adding github.com to known hosts
ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# Configure GitHub access token for pushing to client repositories
# (We're not doing this in prepare.sh because we want to make sure there's no way the
# build/test scripts can accidentally push to GitHub)
echo >>~/.netrc "machine github.com login LaunchDarklyReleaseBot password $(cat $LD_RELEASE_SECRETS_DIR/github_token)"
git config --global user.name LaunchDarklyReleaseBot
git config --global user.email launchdarklyreleasebot@launchdarkly.com

# Publish updates to client repositories
echo Publishing updates to client repositories...
# Temporarily exclude csharp-dotnet2
make RELEASE_TARGETS="go java javascript php python ruby typescript-axios" TAG=${LD_RELEASE_VERSION} push

# Publish client artifacts to registries
echo Publishing client artifacts to registries...
make PUBLISH_TARGETS="java javascript python ruby typescript-axios" publish
