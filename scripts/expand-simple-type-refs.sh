#!/bin/bash

# Temporary workaround for the fact that swagger-codegen doesn't correctly handle $ref's to
# simple types (an alias for a type that's really "string", etc.) in some languages.  We only
# use those for _id properties, so this expands all of those.

sed -e "s@^\( *\)\$ref: ['\"]#/definitions/Id['\"]@\1type: string\\
\1description: The unique resource id.\\
\1example: \"5a580a01b4ff89217bdf9dc1\"@" $1
