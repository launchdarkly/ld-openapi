#!/usr/bin/env bash

set -ue

sed -i.bak -e "s/\( *\)version:\( *\)\([\.0-9]*\)/\1version:\2${LD_RELEASE_VERSION}/" spec/info.yaml
rm -f spec/info.yaml.bak
