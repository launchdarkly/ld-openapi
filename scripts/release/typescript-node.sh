#!/usr/bin/env bash
set -ex

path=$1
name=$2

cd ${path}/
npm install
npm run build
npm publish
