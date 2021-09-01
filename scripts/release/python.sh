#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to PyPI (package was already built by scripts/build/python.sh)
twine upload dist/*
