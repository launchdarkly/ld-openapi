#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Build the package
python3 setup.py bdist_wheel --universal
