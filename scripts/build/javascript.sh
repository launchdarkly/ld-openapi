#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Build the package (or at least, verify that the dependencies work)
npm install
