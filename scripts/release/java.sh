#!/usr/bin/env bash
set -ex

path=$1
name=$2

tmpdir=$(mktemp -d)
trap "rm -rf ${tmpdir}" EXIT

cp -r ${path} $tmpdir
cp ${path}/../../scripts/release/java/publish.gradle ${tmpdir}/$(basename ${path})

cd ${tmpdir}/$(basename ${path})
gradle --info -b publish.gradle publish closeAndReleaseRepository
gradle --info -b publish.gradle publishGhPages
