#!/usr/bin/env bash

# Add artifacts to be picked up by Releaser and added to the ld-openapi GitHub release
echo Generating artifacts...
mkdir -p artifacts
cp targets/openapi.json artifacts
cp targets/openapi.yaml artifacts

cd targets
tar cvfz api-clients-${LD_RELEASE_VERSION}.tgz api-client-*
cd ..
cp targets/api-clients-${LD_RELEASE_VERSION}.tgz artifacts

# Publish updates to client repositories
echo Publishing updates to client repositories...
make TAG=${LD_RELEASE_VERSION} push

# Publish client artifacts to registries
echo Publishing client artifacts to registries...
make PUBLISH_TARGETS="java javascript python ruby" publish
