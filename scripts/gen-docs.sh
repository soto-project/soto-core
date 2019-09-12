#!/bin/sh

set -eux

swift package generate-xcodeproj
jazzy --clean

# stash everything that isn't in docs, store result in STASH_RESULT
STASH_RESULT=$(git stash push -- ":(exclude)docs")
# get branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

git checkout gh-pages
# copy contents of docs to docs/current replacing the ones that are already there
rm -rf docs/current
mv docs/ current/
mkdir docs
mv current/ docs/
# commit
git add --all docs
git commit -m "Publish latest docs"
git push
# return to branch
git checkout $CURRENT_BRANCH

if [ "$STASH_RESULT" != "No local changes to save" ]; then
    git stash pop
fi

