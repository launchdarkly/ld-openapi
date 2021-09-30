#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to Sonatype
PUBLISH_FAILED=
gradle publish closeAndReleaseRepository || PUBLISH_FAILED=1

if [ -n "${PUBLISH_FAILED}" ]; then
  # If publication failed because this version of this package already exists,
  # then we can assume that we're rerunning a partially successful release, so
  # we'll ignore the error and proceed with releasing the other packages.
  echo "Publish failed; checking if version ${LD_RELEASE_VERSION} was already published"
  PACKAGE_METADATA_URL="https://repo1.maven.org/maven2/com/launchdarkly/api-client/${LD_RELEASE_VERSION}/api-client-${LD_RELEASE_VERSION}.pom"
  PACKAGE_EXISTS=
  curl -L --fail --silent "${PACKAGE_METADATA_URL}" >/dev/null 2>/dev/null && PACKAGE_EXISTS=1
  if [ -n "${PACKAGE_EXISTS}" ]; then
    echo "Version ${LD_RELEASE_VERSION} already exists in Maven; proceeding with rest of release"
  else
    echo "Version ${LD_RELEASE_VERSION} was not found in Maven; must assume the release failed"
    exit 1
  fi
fi

# Publish to GitHub Pages
gradle publishGhPages
