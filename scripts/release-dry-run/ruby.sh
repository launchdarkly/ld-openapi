#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Copy the gem we built to the output
mkdir -p ${LD_RELEASE_ARTIFACTS_DIR}/ruby
cp launchdarkly_api-${version}.gem ${LD_RELEASE_ARTIFACTS_DIR}/ruby
