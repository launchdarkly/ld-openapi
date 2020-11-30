#!/usr/bin/env bash
set -ex

path=$1
name=$2

tmpdir=$(mktemp -d)
trap "rm -rf ${tmpdir}" EXIT

cp -r ${path} $tmpdir
cp ${path}/../../scripts/release/java/publish.gradle ${tmpdir}/$(basename ${path})

cd ${tmpdir}/$(basename ${path})
./gradlew --info -b publish.gradle publish closeAndReleaseRepository
./gradlew --info -b publish.gradle publishGhPages
