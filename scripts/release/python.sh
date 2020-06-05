#!/usr/bin/env bash
set -ex

path=$1
name=$2

cd ${path}/
python3 setup.py bdist_wheel --universal
twine upload dist/*
