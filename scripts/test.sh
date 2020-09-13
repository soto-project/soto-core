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

WORKING_DIR=../working

# check if working directory exists and create it if necessary 
[ ! -d $WORKING_DIR ] && mkdir $WORKING_DIR

# run the test on docker containers
docker-compose -f docker/docker-compose.yml up