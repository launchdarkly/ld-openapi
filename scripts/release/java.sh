#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to Sonatype
gradle publish closeAndReleaseRepository

# Publish to GitHub Pages
gradle publishGhPages
