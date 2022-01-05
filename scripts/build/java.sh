#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# "Publish" to the local filesystem - this verifies that the entire build/packaging
# flow works, from compiling through code signing and generating the pom 
./gradlew --stacktrace publishToMavenLocal
