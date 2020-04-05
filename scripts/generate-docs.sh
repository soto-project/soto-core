#!/bin/sh

set -eux

DIRNAME=$(dirname "$0")

source "$DIRNAME"/build-docs.sh
source "$DIRNAME"/commit-docs.sh

