#!/usr/bin/env bash

SG_FOLDER=.build/symbol-graphs
SOTOCORE_SG_FOLDER=.build/soto-core-symbol-graphs
OUTPUT_PATH=docs/soto-core

BUILD_SYMBOLS=1

while getopts 's' option
do
    case $option in
        s) BUILD_SYMBOLS=0;;
    esac
done

# if CI is true assume CI has setup all environment variables
if test "$CI" != "true"; then
    DOCC=$(xcrun --find docc)
    export DOCC_HTML_DIR="$(dirname $DOCC)/../share/docc/render"
fi

if test "$BUILD_SYMBOLS" == 1; then
    # build symbol graphs
    mkdir -p $SG_FOLDER
    swift build \
        -Xswiftc -emit-symbol-graph \
        -Xswiftc -emit-symbol-graph-dir -Xswiftc $SG_FOLDER
    # Copy SotoCore symbol graph into separate folder
    mkdir -p $SOTOCORE_SG_FOLDER
    cp -f $SG_FOLDER/Soto* $SOTOCORE_SG_FOLDER
fi

# Build documentation
mkdir -p $OUTPUT_PATH
rm -rf $OUTPUT_PATH/*
$DOCC convert SotoCore.docc \
    --transform-for-static-hosting \
    --hosting-base-path /soto-core \
    --fallback-display-name SotoCore \
    --fallback-bundle-identifier codes.soto.soto-core \
    --fallback-bundle-version 1 \
    --additional-symbol-graph-dir $SOTOCORE_SG_FOLDER \
    --output-path $OUTPUT_PATH
