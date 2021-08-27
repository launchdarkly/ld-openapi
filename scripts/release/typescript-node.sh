#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to NPM (package was already built by scripts/build/typescript-node.sh)
npm publish
