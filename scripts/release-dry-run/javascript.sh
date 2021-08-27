#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Simulate publishing to NPM
npm publish --dry-run

# Copy the package to the output
npm pack
mkdir -p ${LD_RELEASE_ARTIFACTS_DIR}/javascript
cp *.tgz ${LD_RELEASE_ARTIFACTS_DIR}/javascript
