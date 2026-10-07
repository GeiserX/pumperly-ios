#!/usr/bin/env bash
# Records the typical user flow on the iOS Simulator as an MP4, for App Review.
#
#   scripts/record-demo.sh
#
# Runs on a Mac with Xcode, XcodeGen and network access (the app loads the live site).
# Uses its own simulator, "pumperly-demo", erased on every run: the first-launch screen and
# the location alert show again, the Home Screen starts without the widget, and the recording
# never catches another test run on the shared default simulator.
# Output: $PUMPERLY_DEMO_OUT (default ./out)/pumperly-demo-<version>-<date>.mp4
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
out_dir=${PUMPERLY_DEMO_OUT:-$repo/out}
derived=$repo/build/demo-dd
results=$repo/build/demo-results.xcresult
log=$repo/build/demo-test.log
version=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
out=$out_dir/pumperly-demo-$version-$(date +%Y-%m-%d).mp4
sim_name=pumperly-demo
mkdir -p "$out_dir" build

# Same device model and runtime as the normal test run, on a simulator of our own.
picked=$(scripts/pick-simulator.sh)
read -r device_type runtime sim < <(xcrun simctl list devices --json | python3 -c '
import json, sys
picked, name = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"]
found = {d["udid"]: (r, d) for r, ds in devices.items() for d in ds}
runtime, device = found[picked]
mine = next((d["udid"] for d in devices[runtime] if d["name"] == name and d["isAvailable"]), "-")
print(device["deviceTypeIdentifier"], runtime, mine)
' "$picked" "$sim_name")
if [[ $sim == - ]]; then
  sim=$(xcrun simctl create "$sim_name" "$device_type" "$runtime")
fi
echo "Simulator $sim_name ($sim), $device_type on $runtime"

recorder=
tests=
cleanup() {
  if [[ -n $tests ]] && kill -0 "$tests" 2>/dev/null; then
    kill "$tests"
  fi
  if [[ -n $recorder ]] && kill -0 "$recorder" 2>/dev/null; then
    kill -INT "$recorder"
    wait "$recorder" || true
  fi
}
trap cleanup EXIT

xcrun simctl shutdown "$sim" 2>/dev/null || true
xcrun simctl erase "$sim"
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl status_bar "$sim" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3
xcrun simctl location "$sim" set 40.4168,-3.7038 # Madrid
# Skip the keyboard's one-time swipe-typing tip, which would cover the search.
xcrun simctl spawn "$sim" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true

xcodegen generate --quiet
echo "Building for testing..."
xcodebuild build-for-testing -project Pumperly.xcodeproj -scheme Pumperly \
  -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" -quiet

# A freshly erased simulator spends its first minutes on media and photo analysis, which
# makes the app and XCUITest crawl. Wait until its own processes go quiet (up to 3 minutes).
settle() {
  local launchd busy quiet=0
  launchd=$(pgrep -f "launchd_sim .*Devices/$sim/" | head -1) || return 0
  for _ in $(seq 90); do
    busy=$(ps -Ao ppid=,pcpu= | awk -v p="$launchd" '$1 == p { s += $2 } END { printf "%d", s }')
    if ((busy < 40)); then quiet=$((quiet + 1)); else quiet=0; fi
    ((quiet >= 5)) && return 0
    sleep 2
  done
  echo "The simulator is still busy after 3 minutes; recording anyway"
}
echo "Waiting for the simulator to settle..."
settle

rm -f "$out"
rm -rf "$results"
echo "Running the demo flow..."
TEST_RUNNER_PUMPERLY_DEMO=1 xcodebuild test-without-building -project Pumperly.xcodeproj -scheme Pumperly \
  -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" \
  -only-testing:PumperlyUITests/DemoFlowUITests -parallel-testing-enabled NO \
  -resultBundlePath "$results" >"$log" 2>&1 &
tests=$!

# Installing and starting the test runner takes a minute or two of idle Home Screen. The test
# prints its first "DEMO" line once the app is up, and pauses so the recorder can start.
while ! grep -q '^DEMO ' "$log" && kill -0 "$tests" 2>/dev/null; do sleep 0.5; done
if grep -q '^DEMO ' "$log"; then
  xcrun simctl io "$sim" recordVideo --codec h264 --force "$out" 2>"$repo/build/demo-recorder.log" &
  recorder=$!
  echo "Recording from: $(grep -m1 '^DEMO ' "$log")"
fi

# xcodebuild can hang for minutes after the test has finished; the log says how it went.
finished=
while kill -0 "$tests" 2>/dev/null; do
  if [[ -z $finished ]] && grep -q "^Test Suite 'Selected tests' \(passed\|failed\)" "$log"; then
    finished=$SECONDS
  fi
  if [[ -n $finished ]] && ((SECONDS - finished > 60)); then
    echo "xcodebuild still running 60 s after the test ended; stopping it"
    kill "$tests"
  fi
  sleep 2
done
wait "$tests" || true
tests=
status=0
grep -q "Test Case '.*testDemoFlow\]' passed" "$log" || status=1
grep -E "^DEMO |error:|Test Case .*(passed|failed|skipped)|\*\* TEST" "$log" || true

sleep 2
cleanup
recorder=
[[ -s $out ]] || { echo "No video written: $out" >&2; exit 1; }

if command -v ffprobe >/dev/null; then
  duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$out")
else
  duration=$(mdls -raw -name kMDItemDurationSeconds "$out")
fi
echo "Video:    $out"
printf 'Duration: %.1f s\n' "$duration"
echo "Size:     $(du -h "$out" | cut -f1)"
if [[ $status -ne 0 ]]; then
  echo "The demo flow failed; see $log and $results" >&2
  exit "$status"
fi
