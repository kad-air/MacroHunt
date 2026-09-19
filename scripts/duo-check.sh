#!/usr/bin/env bash
# MacroHunt — iPhone Duo readiness check. Exits non-zero the moment anything is off.
# Copied from ~/Code/Footnotes/scripts/duo-check.sh (itself from Stow; recipe:
# ~/Code/iphone-duo-playbook.md) with MacroHunt defaults. It REUSES any existing iPhone Duo
# simulator (a booted one first) instead of creating a "MacroHunt iPhone Duo" (see DUO_SIM_NAME).
#
# What it proves, against the REAL toolchain and the BUILT product (never project settings):
#   1. the Xcode in use carries an iOS 27.1+ SDK — the SDK a binary links against is what
#      decides how it draws on the Duo's inner display (see CLAUDE.md, "iPhone Duo");
#   2. an iPhone Duo simulator device type and an iOS 27.1+ simulator runtime are installed;
#   3. a Release build for the Duo simulator links against iphonesimulator27.1+, and its built
#      Info.plist still has no UIRequiresFullScreen and declares both device families;
#   4. the app installs, launches and is still alive after a few seconds on the Duo simulator,
#      and every panel that answers is captured, with at least one lit, for eyes-on review;
#   5. (unless SKIP_TESTS=1) the MacroHunt scheme's test action (MacroHuntUITests — DuoBarsUITests,
#      the fails-loud guard on the bar migration) passes on the Duo simulator, and that test is
#      required BY NAME in the .xcresult.
#
# Usage (from anywhere):
#   scripts/duo-check.sh
#   SKIP_TESTS=1 scripts/duo-check.sh
#   DUO_SIM_NAME="iPhone Duo" scripts/duo-check.sh      # pick a specific simulator by name
#
# MacroHunt specifics: never pass CODE_SIGNING_ALLOWED=NO to a build that will be LAUNCHED — an
# unsigned build has no HealthKit entitlement and the app throws a "Missing
# com.apple.developer.healthkit entitlement" alert on launch. Local signing works on the Mac mini
# (automatic, team FBMDY7WDS8).
#
# If DEVELOPER_DIR is unset and the selected Xcode lacks a 27.1 SDK, the script looks for another
# /Applications/Xcode*.app that has one and uses it (printed), so `xcode-select` needn't move.
set -euo pipefail

PROJECT_DIR="${DUO_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"   # the folder holding the .xcodeproj
PROJECT="${DUO_PROJECT:-MacroHunt.xcodeproj}"
SCHEME="${DUO_SCHEME:-MacroHunt}"
BUNDLE_ID="${DUO_BUNDLE_ID:-com.kad-air.MacroHunt}"
# Empty = reuse an existing iPhone Duo simulator on an iOS >= 27.1 runtime (a booted one first);
# only when there is none is "<Scheme> iPhone Duo" created.
SIM_NAME="${DUO_SIM_NAME:-}"
MIN_SDK="27.1"
OUT_DIR="${DUO_CHECK_OUT:-/tmp/macrohunt-duo-check}"
DD="$OUT_DIR/DerivedData"

fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }
ok()   { printf 'ok: %s\n' "$*"; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

cd "$PROJECT_DIR"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ── 1. SDK ──────────────────────────────────────────────────────────────────────────────────
sim_sdk_version() { DEVELOPER_DIR="${1:-${DEVELOPER_DIR:-}}" xcodebuild -showsdks 2>/dev/null \
  | sed -n 's/.*-sdk iphonesimulator\([0-9][0-9.]*\).*/\1/p' | sort -V | tail -1; }

SDK_VER="$(sim_sdk_version)"
if [ -z "$SDK_VER" ] || ! version_ge "$SDK_VER" "$MIN_SDK"; then
  if [ -z "${DEVELOPER_DIR:-}" ]; then
    for app in /Applications/Xcode*.app; do
      cand="$app/Contents/Developer"
      v="$(sim_sdk_version "$cand")"
      if [ -n "$v" ] && version_ge "$v" "$MIN_SDK"; then export DEVELOPER_DIR="$cand"; SDK_VER="$v"; break; fi
    done
  fi
fi
[ -n "$SDK_VER" ] && version_ge "$SDK_VER" "$MIN_SDK" \
  || fail "no Xcode with an iOS Simulator SDK >= $MIN_SDK found (selected: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')). Install Xcode 27.1 beta: xcodes install '27.1 Beta' --experimental-unxip --empty-trash"
ok "iOS Simulator SDK $SDK_VER via ${DEVELOPER_DIR:-$(xcode-select -p)} ($(xcodebuild -version | tr '\n' ' '))"

# ── 2. Runtime + Duo device type ────────────────────────────────────────────────────────────
RUNTIME_LINE="$(xcrun simctl list runtimes available 2>/dev/null | grep -E '^iOS 27\.[1-9]' | sort -V | tail -1 || true)"
[ -n "$RUNTIME_LINE" ] || fail "no iOS >= 27.1 simulator runtime installed. Run: xcodebuild -downloadPlatform iOS (with the 27.1 beta selected / DEVELOPER_DIR set)"
RUNTIME_ID="$(printf '%s' "$RUNTIME_LINE" | sed -n 's/.*- \(com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9-]*\).*/\1/p')"
[ -n "$RUNTIME_ID" ] || fail "could not parse a runtime identifier from: $RUNTIME_LINE"
ok "runtime: $RUNTIME_LINE"

DUO_LINE="$(xcrun simctl list devicetypes 2>/dev/null | grep -i 'duo' | head -1 || true)"
[ -n "$DUO_LINE" ] || fail "no iPhone Duo simulator device type — the runtime installed doesn't carry the Duo simulator"
DUO_TYPE_ID="$(printf '%s' "$DUO_LINE" | sed -n 's/.*(\(com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9-]*\)).*/\1/p')"
[ -n "$DUO_TYPE_ID" ] || fail "could not parse a device type identifier from: $DUO_LINE"
ok "device type: $DUO_LINE"

# ── 3. Simulator (reuse an existing Duo; create only if there is none) ─────────────────────
# Picks from `simctl list -j`: an available device of the Duo type on an iOS >= 27.1 runtime,
# by name if DUO_SIM_NAME is set, otherwise a booted one first, then the first listed.
pick_sim() { xcrun simctl list devices -j 2>/dev/null | python3 -c '
import sys, json
want_name, duo_type = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
cands = []
for runtime, devs in data.get("devices", {}).items():
    tail = runtime.rsplit(".", 1)[-1]          # iOS-27-1
    parts = tail.split("-")
    if len(parts) < 3 or parts[0] != "iOS": continue
    ver = tuple(int(x) for x in parts[1:3])
    if ver < (27, 1): continue
    for d in devs:
        if not d.get("isAvailable", False) or d.get("deviceTypeIdentifier") != duo_type: continue
        if want_name and d.get("name") != want_name: continue
        cands.append((0 if d.get("state") == "Booted" else 1, ver, d))
if cands:
    cands.sort(key=lambda c: (c[0], tuple(-v for v in c[1])))
    d = cands[0][2]
    print(d["udid"], d["state"], d["name"])
' "$SIM_NAME" "$DUO_TYPE_ID"; }
PICK="$(pick_sim || true)"
if [ -n "$PICK" ]; then
  UDID="${PICK%% *}"; REST="${PICK#* }"; SIM_STATE="${REST%% *}"; SIM_NAME="${REST#* }"
  ok "reusing simulator '$SIM_NAME' ($UDID, $SIM_STATE)"
else
  [ -n "$SIM_NAME" ] && fail "no available iPhone Duo simulator named '$SIM_NAME' on an iOS >= $MIN_SDK runtime (xcrun simctl list devices)"
  SIM_NAME="$SCHEME iPhone Duo"
  UDID="$(xcrun simctl create "$SIM_NAME" "$DUO_TYPE_ID" "$RUNTIME_ID")" || fail "simctl create failed"
  ok "no iPhone Duo simulator existed; created '$SIM_NAME' ($UDID)"
fi

# ── 4. Release build for the Duo simulator ─────────────────────────────────────────────────
echo "building Release for the Duo simulator…"
BUILD_LOG="$OUT_DIR/build-$STAMP.log"
set +e
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
  build -quiet > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e
grep -E "error:|warning:" "$BUILD_LOG" | head -20 | sed 's/^/  /' || true
[ "$BUILD_STATUS" -eq 0 ] || fail "Release build for the Duo simulator failed (exit $BUILD_STATUS, log: $BUILD_LOG)"
APP="$DD/Build/Products/Release-iphonesimulator/$SCHEME.app"
[ -d "$APP" ] || fail "built app not found at $APP"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null || true; }
[ "$(plist CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "built bundle id is '$(plist CFBundleIdentifier)', expected $BUNDLE_ID (reading the wrong bundle proves nothing)"
BUILT_SDK="$(plist DTSDKName)"
BUILT_SDK_VER="${BUILT_SDK#iphonesimulator}"
case "$BUILT_SDK" in iphonesimulator*) ;; *) fail "DTSDKName is '$BUILT_SDK', not an iphonesimulator SDK";; esac
version_ge "$BUILT_SDK_VER" "$MIN_SDK" || fail "binary linked against $BUILT_SDK — the Duo's inner display needs >= iphonesimulator$MIN_SDK"
ok "built against $BUILT_SDK (DTPlatformVersion $(plist DTPlatformVersion), Xcode $(plist DTXcode)/$(plist DTXcodeBuild))"
[ "$(plist UIRequiresFullScreen)" != "true" ] || fail "UIRequiresFullScreen is true in the built Info.plist — the app would stop resizing on the Duo"
ok "UIRequiresFullScreen absent/false"
FAMS="$(plist UIDeviceFamily | tr -d ' \n')"
case "$FAMS" in *1*) ;; *) fail "UIDeviceFamily lacks 1 (iPhone): $FAMS";; esac
case "$FAMS" in *2*) ;; *) fail "UIDeviceFamily lacks 2 (iPad): $FAMS";; esac
ok "UIDeviceFamily 1,2"
[ -n "$(plist UILaunchScreen)" ] || [ -n "$(plist UILaunchStoryboardName)" ] || fail "no UILaunchScreen/UILaunchStoryboardName in the built Info.plist — the app would be letterboxed on the Duo instead of resized"
ok "launch screen key present"

# ── 5. Boot, install, launch, stay alive, screenshot ───────────────────────────────────────
xcrun simctl boot "$UDID" 2>/dev/null || true
echo "waiting for '$SIM_NAME' to boot (a Duo runtime's FIRST boot can take several minutes)…"
xcrun simctl bootstatus "$UDID" -b >/dev/null || fail "simulator never reported booted"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" || fail "simctl install failed"
# Land on the Today tab instead of the onboarding sheet: MACROHUNT_DEBUG_ANTHROPIC_KEY seeds a
# bogus key only while none is stored (see CredentialsManager.init), so the capture shows the
# real tab shell and bars.
LAUNCH_OUT="$(SIMCTL_CHILD_MACROHUNT_DEBUG_ANTHROPIC_KEY=duo-check xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1)" || fail "simctl launch failed: $LAUNCH_OUT"
PID="${LAUNCH_OUT##*: }"
[[ "$PID" =~ ^[0-9]+$ ]] || fail "could not parse a pid from: $LAUNCH_OUT"
sleep 8
kill -0 "$PID" 2>/dev/null || fail "$SCHEME (pid $PID) is no longer running 8s after launch on the Duo simulator — it crashed or was killed"
ok "$SCHEME running on '$SIM_NAME' (pid $PID)"

# The Duo has TWO panels and boots CLOSED: the default `simctl io screenshot` is the dark inner
# panel, which reads exactly like "the app didn't draw". Capture every display selector that
# answers (some hang, hence the alarm), keep the ones that produce a file, and require at least one
# to actually be lit. Mean brightness comes from a BMP (uncompressed) so no image library is needed.
# Observed 27.1 b1: `--display=1` = cover 1398×2034 (466×678pt), `--display=3`/`internal` = inner
# 2007×2853 (669×951pt, landscape once open). The pose itself is only switchable in Device Hub.
bmp_brightness() { python3 - "$1" <<'PY'
import sys, struct
b = open(sys.argv[1], 'rb').read()
off = struct.unpack_from('<I', b, 10)[0]
px = b[off::97]                      # stride through the pixel bytes; a sample is plenty
print(int(sum(px) / max(1, len(px))))
PY
}
LIT=0; SHOTS=""
for d in internal 1 2 3 4; do
  BMP="$OUT_DIR/duo-$STAMP-display-$d.bmp"
  # perl forks the capture, kills it after 20 s and exits 124 itself — a plain `alarm; exec`
  # dies by SIGALRM and bash then prints "Alarm clock" for every selector that hangs
  perl -e 'my $p = fork; if (!$p) { exec @ARGV } $SIG{ALRM} = sub { kill 9, $p; waitpid $p, 0; exit 124 }; alarm 20; waitpid $p, 0; exit($? >> 8)' \
    xcrun simctl io "$UDID" screenshot --type=bmp "--display=$d" "$BMP" >/dev/null 2>&1 || { rm -f "$BMP"; continue; }
  [ -s "$BMP" ] || { rm -f "$BMP"; continue; }
  PNG="${BMP%.bmp}.png"; sips -s format png "$BMP" --out "$PNG" >/dev/null 2>&1 && rm -f "$BMP" || PNG="$BMP"
  DIM="$(sips -g pixelWidth -g pixelHeight "$PNG" 2>/dev/null | awk '/pixel/ {v[++n]=$2} END {print v[1] "x" v[2]}')"
  BR="$( [ "${PNG##*.}" = bmp ] && bmp_brightness "$PNG" || { sips -s format bmp "$PNG" --out "$OUT_DIR/.br.bmp" >/dev/null 2>&1 && bmp_brightness "$OUT_DIR/.br.bmp"; } )"; rm -f "$OUT_DIR/.br.bmp"
  echo "  display=$d: $PNG (${DIM}px, mean brightness ${BR:-?})"
  SHOTS="$SHOTS $PNG"
  [ "${BR:-0}" -gt 5 ] && LIT=$((LIT+1))
done
[ -n "$SHOTS" ] || fail "no display selector produced a screenshot"
[ "$LIT" -gt 0 ] || fail "every captured panel is black — $SCHEME is running but nothing is drawing (check Device Hub is attached and which pose the Duo is in)"
ok "$LIT lit panel(s) captured under $OUT_DIR for eyes-on review"

# ── 6. Tests on the Duo simulator ──────────────────────────────────────────────────────────
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "running the $SCHEME scheme's tests on the Duo simulator…"
  TEST_LOG="$OUT_DIR/tests-$STAMP.log"
  # Status is read explicitly, never through a pipeline: an earlier version piped xcodebuild into
  # grep with `|| true`, which reset PIPESTATUS and reported a FAILED UI test as passed.
  set +e
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
    test -quiet > "$TEST_LOG" 2>&1
  TEST_STATUS=$?
  set -e
  grep -E "error:|failed|Executed|TEST (FAILED|SUCCEEDED)" "$TEST_LOG" | grep -v -E "invalidDigitCount|IDESchemeAction" | head -20 | sed 's/^/  /' || true
  # Second source: the xcresult's own counts. Guards both a non-zero exit and a run where no test
  # executed at all (an empty scheme test action exits 0 and proves nothing).
  XCRESULT="$(ls -td "$DD"/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)"
  [ -n "$XCRESULT" ] || fail "no .xcresult under $DD/Logs/Test after the test run (status $TEST_STATUS) — did the scheme run any tests?"
  COUNTS="$(xcrun xcresulttool get test-results summary --path "$XCRESULT" 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(d.get("totalTestCount", 0), d.get("failedTests", 0), d.get("passedTests", 0), d.get("result", "?"))
' 2>/dev/null || echo "0 0 0 unreadable")"
  read -r T_TOTAL T_FAILED T_PASSED T_RESULT <<< "$COUNTS"
  echo "  xcresult: $T_RESULT — $T_PASSED passed, $T_FAILED failed, $T_TOTAL total ($XCRESULT)"
  [ "$TEST_STATUS" -eq 0 ] || fail "xcodebuild test exited $TEST_STATUS on the Duo simulator (log: $TEST_LOG)"
  [ "$T_TOTAL" -gt 0 ] || fail "the xcresult reports zero tests executed — nothing was proven"
  [ "$T_FAILED" -eq 0 ] || fail "$T_FAILED test(s) failed on the Duo simulator per the xcresult (log: $TEST_LOG)"
  # The UI test is the point of the run: require it by name so a scheme that quietly drops
  # MacroHuntUITests can't pass on nothing.
  UI_RUN="$(xcrun xcresulttool get test-results tests --path "$XCRESULT" 2>/dev/null | grep -c "testTabsAndAddMealAreSystemBarItems" || true)"
  [ "${UI_RUN:-0}" -gt 0 ] || fail "DuoBarsUITests.testTabsAndAddMealAreSystemBarItems did not run — is MacroHuntUITests still in the scheme's test action?"
  ok "$T_PASSED tests passed on the Duo simulator incl. DuoBarsUITests (xcodebuild exit 0, xcresult agrees)"
fi

printf '\nDUO CHECK PASSED — Xcode %s, SDK %s, simulator "%s" (%s)\n' \
  "$(xcodebuild -version | head -1 | awk '{print $2}')" "$BUILT_SDK" "$SIM_NAME" "$UDID"
