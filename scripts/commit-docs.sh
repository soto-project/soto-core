#!/bin/sh

set -eux

FOLDER=5.x.x

# stash everything that isn't in docs, store result in STASH_RESULT
STASH_RESULT=$(git stash push -- ":(exclude)docs")
# get branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
REVISION_HASH=$(git rev-parse HEAD)

git checkout gh-pages
# copy contents of docs to docs/current replacing the ones that are already there
rm -rf "$FOLDER"
mv docs/ "$FOLDER"/
# commit
git add --all "$FOLDER"
git commit -m "Documentation for https://github.com/swift-aws/aws-sdk-swift-core/tree/$REVISION_HASH"
git push
# return to branch
git checkout $CURRENT_BRANCH

if [ "$STASH_RESULT" != "No local changes to save" ]; then
    git stash pop
fi

