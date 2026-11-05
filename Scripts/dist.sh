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

mkdir -p build
log=build/dist.log
echo "==> Building Release (log: $log)"
if ! xcodebuild -project Meetball.xcodeproj -scheme Meetball -configuration Release \
    ${arch_args[@]+"${arch_args[@]}"} \
    -allowProvisioningUpdates -derivedDataPath build/DerivedData build >"$log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$log" | tail -20 >&2 || tail -20 "$log" >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi

app=dist/Meetball.app
rm -rf dist && mkdir dist
ditto build/DerivedData/Build/Products/Release/Meetball.app "$app"
echo "==> Built $(pwd)/$app ($(lipo -archs "$app/Contents/MacOS/Meetball"))"

if [ "$install" = 1 ]; then
  pkill -x Meetball 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Meetball.app
  ditto "$app" /Applications/Meetball.app
  app=/Applications/Meetball.app
  echo "==> Installed $app"
fi

if [ "$run" = 1 ]; then
  pkill -x Meetball 2>/dev/null && sleep 1 || true
  echo "==> Opening $app"
  open "$app"
fi
