#!/usr/bin/env bash

# Remove broken libc6-dev (ch77386)
sudo apt-get purge libc6-dev
sudo apt-get autoremove
sudo apt-get clean
sudo apt-get install -f

# Install Python tools and AWS CLI
sudo apt update
sudo apt install awscli python3-pip python3-setuptools
sudo pip3 install wheel twine

# Set up Ruby and RubyGems credentials
sudo apt-get install ruby
mkdir -p ~/.gem
echo -e "---\r\n:rubygems_api_key: $RUBYGEMS_API_KEY" > ~/.gem/credentials
chmod 0600 /home/circleci/.gem/credentials

# Set up git client
git config --global user.name $GH_USER
git config --global user.email $GH_EMAIL

# Fetch credentials
aws s3 cp s3://launchdarkly-pastebin/ci/openapi/gradle.properties.enc .
aws s3 cp s3://launchdarkly-pastebin/ci/openapi/secring.gpg.enc .
openssl enc -d -in gradle.properties.enc -aes-256-cbc -k $ENCRYPTION_SECRET -md md5 > ~/gradle.properties
openssl enc -d -in secring.gpg.enc -aes-256-cbc -k $ENCRYPTION_SECRET -md md5 > ~/secring.gpg

# Prepare configurations needed for client releases
echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" > ~/.npmrc
echo -e "[pypi]\nusername=launchdarkly\npassword=$PYPI_PASSWORD" > ~/.pypirc
