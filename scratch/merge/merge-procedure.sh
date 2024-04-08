#!/bin/bash

set -eux

TIMESTAMP=$(date +"%F-%H-%M")

TARGET=${1:-"hs-backend-merge-${TIMESTAMP}"}

which git-filter-repo || (echo "git-filter-repo required"; exit 2)

if [ -f ${TARGET} ]; then
    echo "Target directory $TARGET exists, aborting script"
    exit 1
fi

# use absolute paths for all subsequent commands
TARGET=$(realpath ${TARGET})

ASSETS="adapt-booster-integration-tests.patch \
        adapt-hlint.patch \
        add-booster-gitignore.patch \
        add-booster-project-config.patch \
        modify-test-workflow.patch \
        modify-release-workflow.patch \
        tweak-booster-fourmolu.patch \
        tweak-nix-flake.patch \
        "

SCRIPTDIR=$(dirname $0)

pushd $SCRIPTDIR

for f in $ASSETS; do
    if [ ! -f "./$f" ]; then
        echo "Missing asset file $f, aborting script"
        exit 1
    fi
done

git clone git@github.com:runtimeverification/haskell-backend.git $TARGET

git clone git@github.com:runtimeverification/hs-backend-booster.git ${TARGET}-booster

pushd ${TARGET}-booster
time git-filter-repo --to-subdirectory-filter booster
popd

cp -t $TARGET $ASSETS

pushd $TARGET
# merge repositories
git checkout -b booster-merge-$TIMESTAMP
git remote add booster ${TARGET}-booster
git fetch booster --no-tags
git merge booster/main --allow-unrelated-histories --no-edit
git remote remove booster

# build setup for all packages
git mv booster/dev-tools ./dev-tools
sed -i -e '/^ *- -eventlog/d' dev-tools/package.yaml
git commit -m "Move dev-tools package to top"
git rm booster/stack.yaml booster/stack.yaml.lock booster/cabal.project booster/.gitignore
sed -i -e '/- stack.yaml/d' booster/package.yaml
patch < add-booster-project-config.patch
patch < add-booster-gitignore.patch
stack ls dependencies
git commit -a -m "Add booster project configuration, remove stale booster files"

# cabal freeze file
git mv -f booster/scripts/freeze-cabal-to-stack-resolver.sh scripts/
git rm booster/cabal.project.freeze
scripts/freeze-cabal-to-stack-resolver.sh
git add ./cabal.project.freeze
git commit -a -m "update cabal freeze file and generating script"

# make flake
git rm booster/flake.nix booster/flake.lock
patch < tweak-nix-flake.patch
nix flake lock
git commit -a -m "flake.nix: add booster artefacts and modify setup, remove booster flake"

# adapt fourmolu and hlint scripts, run them once to check
git mv -f booster/scripts/fourmolu.sh scripts/fourmolu.sh
git rm booster/fourmolu.yaml
scripts/fourmolu.sh -c
git commit -a -m "Adapt fourmolu setup + reformat two booster files"
git mv booster/scripts/hlint.sh scripts/hlint.sh
patch < adapt-hlint.patch
scripts/hlint.sh
git commit -a -m "Adapt hlint setup"

# Adapt booster integration tests and move dependency files
git rm booster/deps/k_release booster/deps/haskell-backend_release
git mv booster/deps/blockchain-k-plugin_release deps/
git mv booster/scripts/integration-tests.sh scripts/booster-integration-tests.sh
patch -p1 < adapt-booster-integration-tests.patch
git commit -a -m "Adapt booster integration test scripts, move dependency information"

# Adapt github workflows
## use merged test workflow
patch -p1 < modify-test-workflow.patch
git rm booster/.github/workflows/test.yml
git commit -a -m "Adapt PR test workflow (adding booster build and integration test)"
## adapt release workflow
patch -p1 < modify-release-workflow.patch
git rm booster/.github/workflows/master.yml
git commit -a -m "Adapt release workflow (populating caches and producing github release)"
## remove old obsolete workflows: update-regression-tests.yml, profiling and kevm performance workflows, with doc.s
git rm .github/workflows/profiling.yaml .github/workflows/kevm-performance-test.yaml docs/2022-11-02-perf-test-automation.md .github/workflows/update-regression-tests.yml
git commit -m "Remove old workflows that are now obsolete"

popd

popd
