#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Try to build the package
# The generated Go code is not a module, so we need to get dependencies first
go get ./...
go build .
