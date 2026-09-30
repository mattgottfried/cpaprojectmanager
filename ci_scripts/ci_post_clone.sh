#!/bin/sh
# Xcode Cloud runs this right after cloning. The .xcodeproj is git-ignored (it is
# generated from project.yml), so build it here before Xcode Cloud looks for it.
set -e
set -o pipefail 2>/dev/null || true

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

# Xcode Cloud turns automatic Swift package resolution off (and pins to a resolved file), and
# the generated project has none yet. Turn resolution back on for this machine, resolve the
# packages (Firebase) so Package.resolved is written into the generated project, and show
# what happened in the log.
defaults write com.apple.dt.Xcode IDEDisableAutomaticPackageResolution -bool NO
defaults write com.apple.dt.Xcode IDEPackageOnlyUseVersionsFromResolvedFile -bool NO

echo "Resolving Swift packages..."
xcodebuild -resolvePackageDependencies -project CPAManager.xcodeproj 2>&1 | tail -40
RESOLVED="CPAManager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [ ! -f "$RESOLVED" ]; then
    echo "error: Package.resolved was not created at $RESOLVED"
    exit 1
fi
echo "Package.resolved created:"
grep -c '"identity"' "$RESOLVED" || true
