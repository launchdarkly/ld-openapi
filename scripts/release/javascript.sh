#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to NPM
PUBLISH_FAILED=
npm publish || PUBLISH_FAILED=1

if [ -n "${PUBLISH_FAILED}" ]; then
  # If publication failed because this version of this package already exists,
  # then we can assume that we're rerunning a partially successful release, so
  # we'll ignore the error and proceed with releasing the other packages.
  echo "Publish failed; checking if version ${LD_RELEASE_VERSION} was already published"
  PACKAGE_NAME=launchdarkly-api
  PACKAGE_EXISTS=
  npm view "${PACKAGE_NAME}@${LD_RELEASE_VERSION}" >/dev/null 2>/dev/null && PACKAGE_EXISTS=1
  if [ -n "${PACKAGE_EXISTS}" ]; then
    echo "Version ${LD_RELEASE_VERSION} already exists in NPM; proceeding with rest of release"
  else
    echo "Version ${LD_RELEASE_VERSION} was not found in NPM; must assume the release failed"
    exit 1
  fi
fi
