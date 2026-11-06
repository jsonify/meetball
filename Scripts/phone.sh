#!/bin/bash
# Builds MeetballPhone and installs it on your iPhone without opening Xcode.
#
#   Scripts/phone.sh                  build, install on the reachable iPhone, and open it
#   PHONE="Big Ol" Scripts/phone.sh   pick the iPhone by (part of) its name or identifier when more than one is reachable
#   Scripts/phone.sh --no-launch      install without opening it
#
# The iPhone must be paired with this Mac (connected once by cable and trusted; after that Wi-Fi works) and unlocked.
# The full xcodebuild log is kept at build/phone.log.
set -euo pipefail
cd "$(dirname "$0")/.."

launch=1
for arg in "$@"; do
  case "$arg" in
    --no-launch) launch=0 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
mkdir -p build

# Find the iPhone: paired and reachable (by cable or Wi-Fi), narrowed by $PHONE when set.
devices=build/phone-devices.json
xcrun devicectl list devices --json-output "$devices" >/dev/null 2>&1 || { echo "Couldn't list devices (is Xcode installed?)" >&2; exit 1; }
pick=$(PHONE="${PHONE:-}" python3 -I - "$devices" <<'PY'
import json, os, sys
want = os.environ["PHONE"].lower()
phones = [d for d in json.load(open(sys.argv[1]))["result"]["devices"]
          if d["hardwareProperties"].get("deviceType") == "iPhone"
          and d["connectionProperties"].get("pairingState") == "paired"]
reachable = [d for d in phones if d["connectionProperties"].get("transportType")]
if want:
    reachable = [d for d in reachable if want in d["deviceProperties"]["name"].lower() or want in d["identifier"].lower()]
if len(reachable) != 1:
    names = ", ".join(d["deviceProperties"]["name"] for d in (reachable or phones)) or "none"
    why = "No reachable iPhone matches" if not reachable else "More than one iPhone is reachable"
    print(f"{why} (paired: {names}). Unlock it, keep it on the same Wi-Fi or plug it in; set PHONE=\"name\" to choose.",
          file=sys.stderr)
    sys.exit(1)
d = reachable[0]
print(d["identifier"], d["hardwareProperties"]["udid"], d["deviceProperties"]["name"], sep="\t")
PY
)
IFS=$'\t' read -r device udid name <<<"$pick"
echo "==> iPhone: $name"

echo "==> Generating Meetball.xcodeproj"
xcodegen generate --quiet

build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if ! git diff --quiet HEAD -- 2>/dev/null; then commit="$commit-dirty"; fi
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log=build/phone.log
if pgrep -f "xcodebuild.*-derivedDataPath build/DerivedDataPhone" >/dev/null 2>&1; then
  echo "Another iPhone build is still running (an earlier make in another tab?). Wait for it, or: pkill xcodebuild" >&2
  exit 1
fi
echo "==> Building MeetballPhone Release (log: $log)"
if ! xcodebuild -project Meetball.xcodeproj -scheme MeetballPhone -configuration Release \
    -destination "id=$udid" CURRENT_PROJECT_VERSION="$build_number" MEETBALL_COMMIT="$commit" MEETBALL_BUILD_DATE="$build_date" \
    -allowProvisioningUpdates -derivedDataPath build/DerivedDataPhone build >"$log" 2>&1; then
  grep -aE "error:|BUILD FAILED" "$log" | tail -20 >&2 || tail -20 "$log" >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi

app=build/DerivedDataPhone/Build/Products/Release-iphoneos/MeetballPhone.app
[ -d "$app" ] || { echo "Built app not found at $app" >&2; exit 1; }
echo "==> Installing on $name (build $build_number, $commit)"
xcrun devicectl device install app --device "$device" "$app" >>"$log" 2>&1 \
  || { tail -15 "$log" >&2; echo "Install failed. Is the iPhone unlocked? Full log: $log" >&2; exit 1; }

if [ "$launch" = 1 ]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
  if xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id" >>"$log" 2>&1; then
    echo "==> Opened Meetball on $name"
  else
    echo "Installed, but couldn't open it (the iPhone may be locked). Open Meetball on the phone."
  fi
fi
echo "==> Done"
