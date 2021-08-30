#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Build the package
npm install
npm run build

# Simulate publishing to NPM
npm publish --dry-run

# Copy the package to the output
npm pack
mkdir -p ${LD_RELEASE_ARTIFACTS_DIR}/typescript-axios
cp *.tgz ${LD_RELEASE_ARTIFACTS_DIR}/typescript-axios
