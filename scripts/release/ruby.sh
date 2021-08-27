#!/usr/bin/env bash
set -ex

path=$1
name=$2
version=$3

cd ${path}

# Publish to RubyGems (gem was already built by scripts/build/ruby.sh)
gem push launchdarkly_api-${version}.gem
