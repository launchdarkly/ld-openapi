#!/usr/bin/env bash

set -eu

make

# Copy the build products into $LD_RELEASE_ARTIFACTS_DIR so that in an actual
# release they will be automatically attached as assets to the GitHub release;
# in a dry run they will be downloadable from Releaser.

# Add spec artifacts to be picked up by Releaser and added to the ld-openapi GitHub release
echo Generating artifacts...
cp targets/openapi.json ${LD_RELEASE_ARTIFACTS_DIR}
cp targets/openapi.yaml ${LD_RELEASE_ARTIFACTS_DIR}

# Add client artifacts to be picked up by Releaser and added to the ld-openapi GitHub release
cd targets
tar cvfz api-clients-${LD_RELEASE_VERSION}.tgz api-client-*
cd ..
cp targets/api-clients-${LD_RELEASE_VERSION}.tgz ${LD_RELEASE_ARTIFACTS_DIR}

# Verify that the generated client code can be built
make BUILD_TARGETS="go java javascript python ruby typescript-node" build_clients
