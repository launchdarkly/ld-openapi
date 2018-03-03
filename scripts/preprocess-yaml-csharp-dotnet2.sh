#!/bin/bash

# swagger-codegen for C# doesn't correctly handle aliases for simple types
$(dirname "$0")/../scripts/expand-simple-type-refs.sh $1
