#!/bin/sh

set -eux

# make temp directory
mkdir -p sourcekitten

# generate source kitten json
sourcekitten doc --spm-module "AWSSDKSwiftCore" > sourcekitten/AWSSDKSwiftCore.json;
sourcekitten doc --spm-module "AWSSigner" > sourcekitten/AWSSigner.json;

# generate documentation with jazzy
jazzy --clean

# tidy up
rm -rf sourcekitten
rm -rf docs/docsets
