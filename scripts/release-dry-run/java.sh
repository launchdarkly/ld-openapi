#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Copy the publishable artifacts from the build step to the dry run output
mkdir -p ${LD_RELEASE_ARTIFACTS_DIR}/java
cp -r ~/.m2/repository/com/launchdarkly/api-client/${version}/* ${LD_RELEASE_ARTIFACTS_DIR}/java
