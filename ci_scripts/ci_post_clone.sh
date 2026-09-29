#!/bin/sh
# Xcode Cloud runs this right after cloning. The .xcodeproj is git-ignored (it is
# generated from project.yml), so build it here before Xcode Cloud looks for it.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Avoid slow auto-updates / cleanup on the CI image.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen
fi

xcodegen generate
