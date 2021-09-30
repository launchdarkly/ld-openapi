#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to RubyGems (gem was already built by scripts/build/ruby.sh)
PUBLISH_FAILED=
gem push launchdarkly_api-${version}.gem || PUBLISH_FAILED=1

if [ -n "${PUBLISH_FAILED}" ]; then
  # If publication failed because this version of this package already exists,
  # then we can assume that we're rerunning a partially successful release, so
  # we'll ignore the error and proceed with releasing the other packages.
  echo "Publish failed; checking if version ${LD_RELEASE_VERSION} was already published"
  # See: https://guides.rubygems.org/rubygems-org-api/
  PACKAGE_NAME=launchdarkly_api
  PACKAGE_METADATA_URL="https://rubygems.org/api/v1/versions/${PACKAGE_NAME}/latest.json"
  FOUND_VERSION_IN_JSON=$(curl -L --fail --silent "${PACKAGE_METADATA_URL}" 2>/dev/null | \
  	grep "\"${LD_RELEASE_VERSION}\"")
  if [ -n "${FOUND_VERSION_IN_JSON}" ]; then
    echo "Version ${LD_RELEASE_VERSION} already exists in RubyGems; proceeding with rest of release"
  else
    echo "Version ${LD_RELEASE_VERSION} was not found in RubyGems; must assume the release failed"
    exit 1
  fi
fi
