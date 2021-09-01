#!/usr/bin/env bash

set -eu

# Set up credentials needed for client package releases. These have been downloaded
# by Releaser into $LD_RELEASE_SECRETS_DIR as specified by our secrets.properties file.
# We'll put them into the standard locations used by the various build/release tools -
# in some cases we could put them in environment variables instead, but then it would
# be harder to use the release scripts locally outside of Releaser.

# Gradle properties and signing key
java_sonatype_username="$(cat "${LD_RELEASE_SECRETS_DIR}/java_sonatype_username")"
java_sonatype_password="$(cat "${LD_RELEASE_SECRETS_DIR}/java_sonatype_password")"
mkdir -p ~/.gradle
cat >~/.gradle/gradle.properties <<EOF
signing.keyId = BFF924E9
signing.password = 
signing.secretKeyRingFile = ${LD_RELEASE_SECRETS_DIR}/java_code_signing_keyring
ossrhUsername = ${java_sonatype_username}
ossrhPassword = ${java_sonatype_password}
nexusUsername = ${java_sonatype_username}
nexusPassword = ${java_sonatype_password}
systemProp.org.gradle.internal.launcher.welcomeMessageEnabled = false
EOF

# NPM token
npm_auth_token="$(cat "${LD_RELEASE_SECRETS_DIR}/npm_auth_token")"
echo "//registry.npmjs.org/:_authToken=${npm_auth_token}" > ~/.npmrc

# PyPI token
python_pypi_token="$(cat "${LD_RELEASE_SECRETS_DIR}/python_pypi_token")"
echo -e "[pypi]\nusername=launchdarkly\npassword=${python_pypi_token}" > ~/.pypirc

# RubyGems API key
rubygems_api_key="$(cat "${LD_RELEASE_SECRETS_DIR}/ruby_gems_api_key")"
mkdir -p ~/.gem
echo -e "---\r\n:rubygems_api_key: ${rubygems_api_key}" > ~/.gem/credentials
chmod 0600 ~/.gem/credentials
