#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to PyPI (package was already built by scripts/build/python.sh)
PUBLISH_FAILED=
twine upload dist/* || PUBLISH_FAILED=1

if [ -n "${PUBLISH_FAILED}" ]; then
  # If publication failed because this version of this package already exists,
  # then we can assume that we're rerunning a partially successful release, so
  # we'll ignore the error and proceed with releasing the other packages.
  echo "Publish failed; checking if version ${LD_RELEASE_VERSION} was already published"
  # See: https://warehouse.pypa.io/api-reference/json.html
  PACKAGE_NAME=launchdarkly-api
  PACKAGE_METADATA_URL="https://pypi.org/pypi/${PACKAGE_NAME}/${LD_RELEASE_VERSION}/json"
  PACKAGE_EXISTS=
  curl -L --fail --silent "${PACKAGE_METADATA_URL}" >/dev/null 2>/dev/null && PACKAGE_EXISTS=1
  if [ -n "${PACKAGE_EXISTS}" ]; then
    echo "Version ${LD_RELEASE_VERSION} already exists in PyPI; proceeding with rest of release"
  else
    echo "Version ${LD_RELEASE_VERSION} was not found in PyPI; must assume the release failed"
    exit 1
  fi
fi
