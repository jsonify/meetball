#!/bin/bash
# Builds a Release Meetball.app into ./dist without opening Xcode.
#
#   Scripts/dist.sh              build dist/Meetball.app
#   Scripts/dist.sh --run        build, then quit any running Meetball and open the new one
#   Scripts/dist.sh --install    build, then copy it to /Applications (and open it with --run)
#   Scripts/dist.sh --universal  build for arm64 + x86_64 instead of this Mac's architecture
#
# Flags combine. The full xcodebuild log is kept at build/dist.log.
set -euo pipefail
cd "$(dirname "$0")/.."

run=0; install=0; universal=0
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    --install) install=1 ;;
    --universal) universal=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

echo "==> Generating Meetball.xcodeproj"
xcodegen generate --quiet

arch_args=()
if [ "$universal" = 1 ]; then
  arch_args=(-destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi

# Stamp the build so Settings › General and About Meetball say exactly which one is running: the build number is the
# commit count, plus the short hash ("-dirty" when there are uncommitted changes) and the build time.
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if ! git diff --quiet HEAD -- 2>/dev/null; then commit="$commit-dirty"; fi
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
version_args=(CURRENT_PROJECT_VERSION="$build_number" MEETBALL_COMMIT="$commit" MEETBALL_BUILD_DATE="$build_date")

mkdir -p build
log=build/dist.log
# Two builds sharing build/DerivedData fail with "database is locked"; say so up front instead.
if pgrep -f "xcodebuild.*-derivedDataPath build/DerivedData" >/dev/null 2>&1; then
  echo "Another Meetball build is still running (an earlier make in another tab?). Wait for it, or: pkill xcodebuild" >&2
  exit 1
fi
echo "==> Building Release (log: $log)"
if ! xcodebuild -project Meetball.xcodeproj -scheme Meetball -configuration Release \
    ${arch_args[@]+"${arch_args[@]}"} "${version_args[@]}" \
    -allowProvisioningUpdates -derivedDataPath build/DerivedData build >"$log" 2>&1; then
  # -a: xcodebuild logs can hold bytes that make grep call the file binary and print nothing useful.
  grep -aE "error:|BUILD FAILED" "$log" | tail -20 >&2 || tail -20 "$log" >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi

app=dist/Meetball.app
rm -rf dist && mkdir dist
ditto build/DerivedData/Build/Products/Release/Meetball.app "$app"
# The Dock and Finder show a blank placeholder when the app icon didn't make it into the bundle: say so now.
if [ ! -f "$app/Contents/Resources/AppIcon.icns" ]; then
  echo "warning: $app has no AppIcon.icns, so it will show a blank icon (check Meetball/Assets.xcassets)" >&2
fi
echo "==> Built $(pwd)/$app (build $build_number, $commit, $(lipo -archs "$app/Contents/MacOS/Meetball"))"

if [ "$install" = 1 ]; then
  pkill -x Meetball 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Meetball.app
  ditto "$app" /Applications/Meetball.app
  app=/Applications/Meetball.app
  echo "==> Installed $app"
fi

# Tell Launch Services about this copy, so the Dock and Finder drop any icon they cached for an older build.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
touch "$app"
[ -x "$lsregister" ] && "$lsregister" -f "$app" >/dev/null 2>&1 || true

if [ "$run" = 1 ]; then
  pkill -x Meetball 2>/dev/null && sleep 1 || true
  echo "==> Opening $app"
  open "$app"
fi
