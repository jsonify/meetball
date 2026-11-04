#!/bin/zsh
# Builds a universal (arm64 + x86_64) Release app and copies it to ./dist
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Meetball.xcodeproj -scheme Meetball -configuration Release \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  -allowProvisioningUpdates -derivedDataPath build/DerivedData build | tail -3
rm -rf dist && mkdir dist
ditto build/DerivedData/Build/Products/Release/Meetball.app dist/Meetball.app
echo "Built: $(pwd)/dist/Meetball.app"
lipo -archs dist/Meetball.app/Contents/MacOS/Meetball
codesign -dv dist/Meetball.app 2>&1 | grep -E "Authority=Apple Dev|TeamIdentifier"
