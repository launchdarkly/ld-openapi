#!/usr/bin/env bash
set -ex

path=$1
name=$2

dir=$(mktemp -d)
trap "rm -rf ${dir}" EXIT

package="${dir}/$(basename ${path})"
cp -r ${path} ${package}
jq ".private=false" ${path}/package.json > ${package}/package.json

cd ${package}/
npm publish
