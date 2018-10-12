#!/usr/bin/env bash
set -ex

path=$1
name=$2

cd ${patch}/
npm publish
