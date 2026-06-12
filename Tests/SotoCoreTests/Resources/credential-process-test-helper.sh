#!/bin/sh
#===----------------------------------------------------------------------===#
#
# This source file is part of the Soto for AWS open source project
#
# Copyright (c) 2017-2026 the Soto project authors
# Licensed under Apache License v2.0
#
# See LICENSE.txt for license information
# See CONTRIBUTORS.txt for the list of Soto project authors
#
# SPDX-License-Identifier: Apache-2.0
#
#===----------------------------------------------------------------------===#

# Test helper script for CredentialProcessProvider tests.
# Mimics the output of a credential_process command as defined by the AWS CLI spec.
# Accepts flags to control output for different test scenarios.

# Check for flags
INVALID_JSON=false
INVALID_VERSION=false
EXPIRING=false
NO_SESSION_TOKEN=false
EXIT_CODE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --invalid-json)
            INVALID_JSON=true
            shift
            ;;
        --invalid-version)
            INVALID_VERSION=true
            shift
            ;;
        --expiring)
            EXPIRING=true
            shift
            ;;
        --no-session-token)
            NO_SESSION_TOKEN=true
            shift
            ;;
        --exit-code)
            EXIT_CODE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Handle --invalid-json: output garbage and exit
if [ "$INVALID_JSON" = true ]; then
    echo "this is not json{{{"
    exit 0
fi

# Handle --exit-code: exit with the specified code
if [ -n "$EXIT_CODE" ]; then
    exit "$EXIT_CODE"
fi

# Build the JSON output
VERSION=1
if [ "$INVALID_VERSION" = true ]; then
    VERSION=2
fi

# Start building JSON fields
FIELDS="\"Version\":$VERSION,\"AccessKeyId\":\"AKID-CREDENTIAL-PROCESS\",\"SecretAccessKey\":\"SECRET-CREDENTIAL-PROCESS\""

if [ "$NO_SESSION_TOKEN" = false ]; then
    FIELDS="$FIELDS,\"SessionToken\":\"TOKEN-CREDENTIAL-PROCESS\""
fi

if [ "$EXPIRING" = true ]; then
    # Generate an ISO8601 date 1 hour in the future
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        EXPIRATION=$(date -u -d "+1 hour" "+%Y-%m-%dT%H:%M:%SZ")
    else
        # BSD date (macOS)
        EXPIRATION=$(date -u -v+1H "+%Y-%m-%dT%H:%M:%SZ")
    fi
    FIELDS="$FIELDS,\"Expiration\":\"$EXPIRATION\""
fi

echo "{$FIELDS}"
