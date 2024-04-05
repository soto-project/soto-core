#!/usr/bin/env bash
set -eux

TEMP_DIR="$(pwd)/temp"

cleanup()
{
    if [ -n "$TEMP_DIR" ]; then
        rm -rf $TEMP_DIR
    fi
}
trap cleanup exit $?

#DOCC=$(xcrun --find docc)
DOCC=docc
VERSION=7.x.x
SG_FOLDER=.build/symbol-graphs
SOTOCORE_SG_FOLDER=.build/soto-core-symbol-graphs
OUTPUT_PATH=docs/soto-core/$VERSION

BUILD_SYMBOLS=1

while getopts 's' option
do
    case $option in
        s) BUILD_SYMBOLS=0;;
    esac
done

if [ -z "${DOCC_HTML_DIR:-}" ]; then
    git clone https://github.com/apple/swift-docc-render-artifact $TEMP_DIR/swift-docc-render-artifact
     export DOCC_HTML_DIR="$TEMP_DIR/swift-docc-render-artifact/dist"
fi

if test "$BUILD_SYMBOLS" == 1; then
    # build symbol graphs
    mkdir -p $SG_FOLDER
    swift build \
        -Xswiftc -emit-symbol-graph \
        -Xswiftc -emit-symbol-graph-dir -Xswiftc $SG_FOLDER
    # Copy SotoCore symbol graph into separate folder
    mkdir -p $SOTOCORE_SG_FOLDER
    cp $SG_FOLDER/SotoCore* $SOTOCORE_SG_FOLDER
    cp $SG_FOLDER/SotoSignerV4* $SOTOCORE_SG_FOLDER
fi

# Build documentation
mkdir -p $OUTPUT_PATH
rm -rf $OUTPUT_PATH/*
$DOCC convert SotoCore.docc \
    --transform-for-static-hosting \
    --hosting-base-path /soto-core/$VERSION \
    --fallback-display-name SotoCore \
    --fallback-bundle-identifier codes.soto.soto-core \
    --fallback-bundle-version 1 \
    --additional-symbol-graph-dir $SOTOCORE_SG_FOLDER \
    --output-path $OUTPUT_PATH
