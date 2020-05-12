#!/bin/sh
##===----------------------------------------------------------------------===##
##
## This source file is part of the AWSSDKSwift open source project
##
## Copyright (c) 2020 the AWSSDKSwift project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eux

# make temp directory
mkdir -p sourcekitten

# generate source kitten json
sourcekitten doc --spm-module "AWSSDKSwiftCore" > sourcekitten/AWSSDKSwiftCore.json;
sourcekitten doc --spm-module "AWSSignerV4" > sourcekitten/AWSSignerV4.json;

# generate documentation with jazzy
jazzy --clean

# tidy up
rm -rf sourcekitten
rm -rf docs/docsets
