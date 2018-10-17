#!/usr/bin/env bash
set -ex

path=$1
name=$2

cd ${path}/
npm publish
