#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Build the gem
gem build launchdarkly_api.gemspec
