#!/usr/bin/env bash
# sk1-audit: lists what in a SwiftUI app still looks native next to the SK-1 look, with the SK1Kit part to use
# instead (DESIGN.md, "Adopting SK1Kit"). Run it on an app's sources:
#
#   Scripts/sk1-audit.sh path/to/App            # every .swift file under it
#   Scripts/sk1-audit.sh --warn path/to/App     # report, but exit 0
#
# Each finding is "file:line: [rule] what to use instead". It exits 1 when there are findings (0 with --warn), so it
# can gate CI once an app has adopted the kit. A line ending in `// sk1-audit: ignore` is skipped: use it where a
# native control is meant to stay (a full-screen overlay with its own look, a system sheet).
set -euo pipefail

warn_only=0
if [[ "${1:-}" == "--warn" ]]; then warn_only=1; shift; fi
if [[ $# -lt 1 ]]; then
  echo "usage: $0 [--warn] <path>..." >&2
  exit 2
fi

# rule id ~~ extended regex ~~ what to use instead
rules=(
  'picker ~~ (^|[^A-Za-z])Picker[[:space:]]*\( ~~ SKPicker (◀ chip ▶, or stepper: false for a pop-up); SKSegmented for 2-4 choices'
  'segmented ~~ \.pickerStyle\(\.segmented\) ~~ SKSegmented'
  'stepper ~~ (^|[^A-Za-z])Stepper[[:space:]]*\( ~~ SKKnob (smooth) or SKPicker'
  'slider ~~ (^|[^A-Za-z])Slider[[:space:]]*\( ~~ SKKnob(_:value:in:step:defaultValue:format:)'
  'divider ~~ (^|[^A-Za-z])Divider[[:space:]]*\(\) ~~ SKGroove() (or SKGroove(.vertical))'
  'prominent ~~ \.borderedProminent ~~ .buttonStyle(.sk1Key(.orange)) — one orange key per screen'
  'bordered ~~ \.buttonStyle\(\.bordered\) ~~ .buttonStyle(.sk1Key()) (cream) or .sk1Key(.charcoal) for an action apart'
  'link-button ~~ \.buttonStyle\(\.link\) ~~ .buttonStyle(.sk1Key(size: .small)) or SKCaptionedKey'
  'accent ~~ accentColor ~~ Color(sk1Hex: SK1.orange) for what is on; SKLamp for state'
  'material ~~ \.(ultraThin|thin|regular|thick|ultraThick)Material ~~ .sk1Chassis() for a window, SKPlate for a card, SKWell for a tray'
  'groupbox ~~ (^|[^A-Za-z])GroupBox[[:space:]]*[({] ~~ SKWell or SKGroup(caption:)'
  'form ~~ (^|[^A-Za-z])Form[[:space:]]*[{] ~~ SKGroup(caption:) of SKRow(title:subtitle:), in a scrolling pane on the chassis'
  'textfield ~~ (^|[^A-Za-z])TextField[[:space:]]*\( ~~ SKTextField'
  'uppercase ~~ \.textCase\(\.uppercase\) ~~ SKCaption (tracked, sized and spoken in normal case)'
  'progress-ring ~~ \.trim\(from: ~~ an LCD (SKDisplay, SKSevenSegment, SKElapsed) for live numbers'
)

# A Toggle is fine once it has an SK-1 style on its line or within the next few (its label, binding or other modifiers
# can take several lines).
toggle_rule='(^|[^A-Za-z])Toggle[[:space:]]*\('
toggle_lookahead=5

files=()
for path in "$@"; do
  if [[ -d "$path" ]]; then
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$path" -name '*.swift' -not -path '*/.build/*' -print0 | sort -z)
  elif [[ -f "$path" ]]; then
    files+=("$path")
  else
    echo "sk1-audit: no such file or directory: $path" >&2
    exit 2
  fi
done

count=0
report() {   # file line rule hint
  echo "$1:$2: [$3] $4"
  count=$((count + 1))
}

for f in "${files[@]}"; do
  n=0
  pending_toggle=""
  pending_left=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    # A Toggle on an earlier line: styled here, still waiting, or out of lines (or another Toggle starts) and reported.
    if [[ -n "$pending_toggle" ]]; then
      if [[ "$line" =~ toggleStyle\(\.sk1 ]]; then
        pending_toggle=""
      else
        pending_left=$((pending_left - 1))
        if [[ $pending_left -le 0 || "$line" =~ $toggle_rule ]]; then
          report "$f" "$pending_toggle" toggle '.toggleStyle(.sk1Switch) in a row, .sk1Square in a bar'
          pending_toggle=""
        fi
      fi
    fi
    [[ "$line" =~ sk1-audit:[[:space:]]*ignore ]] && continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ "$trimmed" == //* ]] && continue
    for rule in "${rules[@]}"; do
      id="${rule%% ~~ *}"; rest="${rule#* ~~ }"; re="${rest%% ~~ *}"; hint="${rest#* ~~ }"
      if [[ "$line" =~ $re ]]; then report "$f" "$n" "$id" "$hint"; fi
    done
    if [[ "$line" =~ $toggle_rule ]] && ! [[ "$line" =~ toggleStyle\(\.sk1 ]]; then
      pending_toggle=$n
      pending_left=$toggle_lookahead
    fi
  done < "$f"
  if [[ -n "$pending_toggle" ]]; then report "$f" "$pending_toggle" toggle '.toggleStyle(.sk1Switch) in a row, .sk1Square in a bar'; fi
done

if [[ $count -eq 0 ]]; then
  echo "sk1-audit: nothing native left in ${#files[@]} file(s)."
  exit 0
fi
echo "sk1-audit: $count finding(s) in ${#files[@]} file(s)." >&2
[[ $warn_only -eq 1 ]] && exit 0
exit 1
