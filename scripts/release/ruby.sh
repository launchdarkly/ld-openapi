#!/usr/bin/env bash
set -ex

path=$1
name=$2

cd ${path}/
gem build launchdarkly_api.gemspec
gem push launchdarkly_api
