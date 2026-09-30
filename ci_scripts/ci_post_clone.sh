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

# Firebase config: kept out of git, supplied to Xcode Cloud as a secret environment variable
# (base64 of GoogleService-Info.plist). Without it the app still builds and runs, local-only.
if [ -n "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
    mkdir -p CPAManager/Resources
    echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > CPAManager/Resources/GoogleService-Info.plist
fi

xcodegen generate
