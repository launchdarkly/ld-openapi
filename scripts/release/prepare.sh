#!/usr/bin/env bash

set -eu

# Set up credentials needed for client package releases.
#
# Gradle properties and signing key
mkdir -p ~/.gradle
cat >~/.gradle/gradle.properties <<EOF
signing.keyId = BFF924E9
signing.password = 
signing.secretKeyRingFile = ${HOME}/code-signing-keyring.gpg
ossrhUsername = ${SONATYPE_USERNAME}
ossrhPassword = ${SONATYPE_PASSWORD}
nexusUsername = ${SONATYPE_USERNAME}
nexusPassword = ${SONATYPE_PASSWORD}
systemProp.org.gradle.internal.launcher.welcomeMessageEnabled = false
EOF

# NPM token
echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > ~/.npmrc

# PyPI token
echo -e "[pypi]\nusername=__token__\npassword=${PYPI_TOKEN}" > ~/.pypirc

# RubyGems API key
mkdir -p ~/.gem
echo -e "---\r\n:rubygems_api_key: ${RUBYGEM_API_KEY}" > ~/.gem/credentials
chmod 0600 ~/.gem/credentials
