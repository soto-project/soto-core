#!/bin/sh
##===----------------------------------------------------------------------===##
##
## This source file is part of the Soto for AWS open source project
##
## Copyright (c) 2020 the Soto project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of Soto project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eux

# make temp directory
mkdir -p sourcekitten

# generate source kitten json
sourcekitten doc --spm-module "SotoCore" > sourcekitten/SotoCore.json;

# generate documentation with jazzy
jazzy --clean

# tidy up
rm -rf sourcekitten
rm -rf docs/docsets
