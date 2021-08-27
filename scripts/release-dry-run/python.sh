#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Copy the package we built to the output
mkdir -p ${LD_RELEASE_ARTIFACTS_DIR}/python
cp dist/* ${LD_RELEASE_ARTIFACTS_DIR}/python
