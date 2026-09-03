#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

TEST_ROOT="${LOGIC_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-control-capability-session}"
ZIP_PATH="${OUT_DIR}.zip"
EXPECTED="${A1_EXPECTED:-}"

rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR/mixer" "$OUT_DIR/inventory"

SESSION_START=$SECONDS
STEP_START=$SECONDS
PASS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
CRITICAL=0
LAB=""
CONTROL=""
A1CMP=""

bar() {
  local pct="$1" width=20 filled empty s="" i
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$((pct * width / 100))
  empty=$((width - filled))
  for ((i=0; i<filled; i++)); do s="${s}█"; done
  for ((i=0; i<empty; i++)); do s="${s}░"; done
  printf "%s" "$s"
}

fmt_time() {
  local t="$1"
  printf "%02dm %02ds" $((t / 60)) $((t % 60))
}

progress() {
  local overall="$1" current="$2" step_no="$3" step_name="$4" detail="$5"
  local elapsed=$((SECONDS - SESSION_START))
  local step_elapsed=$((SECONDS - STEP_START))
  local eta="calculating"
  if (( overall > 3 )); then
    eta="~$(fmt_time $((elapsed * (100 - overall) / overall)))"
  fi
  echo
  printf "Overall  [%s] %3d%%   Step %s of 8\n" "$(bar "$overall")" "$overall" "$step_no"
  printf "Current  [%s] %3d%%   %s\n" "$(bar "$current")" "$current" "$step_name"
  printf "Action:   %s\n" "$detail"
  printf "Elapsed overall: %s | current step: %s | ETA: %s\n" "$(fmt_time "$elapsed")" "$(fmt_time "$step_elapsed")" "$eta"
}

begin_step() { STEP_START=$SECONDS; }

zip_evidence() {
  (
    cd "$(dirname "$OUT_DIR")" || return 1
    /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
  )
}

record() {
  local kind="$1" label="$2" detail="$3"
  printf "%s\t%s\t%s\n" "$kind" "$label" "$detail" >>"$OUT_DIR/results.tsv"
  case "$kind" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1));;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1));;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1));;
  esac
}

abort() {
  local message="$1"
  CRITICAL=1
  echo "CRITICAL: $message" >&2
  record FAIL "critical" "$message"
  {
    echo "Logic Co-Producer control capability validation"
    echo "RESULT=FAIL"
    echo "Critical reason: $message"
    echo "Elapsed: $(fmt_time $((SECONDS - SESSION_START)))"
    echo "PASS=$PASS_COUNT SKIP=$SKIP_COUNT FAIL=$FAIL_COUNT"
  } >"$OUT_DIR/SUMMARY.txt"
  zip_evidence >/dev/null 2>&1 || true
  echo "Partial evidence: $ZIP_PATH" >&2
  exit 1
}

capture_midi() {
  local json="$1" log="$2"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$json" >"$log" 2>&1 || return 1
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$log" || return 1
  grep -q 'rows_with_position=267 of 267' "$log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$log" || return 1
}

run_roundtrip() {
  local kind="$1" query="$2" slug="$3" label="$4"
  local out="$OUT_DIR/mixer/$slug.json"
  local log="$OUT_DIR/mixer/$slug.log"
  "$CONTROL" "$kind" --query "$query" --out "$out" >"$log" 2>&1
  local status=$?
  if [[ "$status" -eq 0 ]] && grep -q 'RESULT=PASS' "$log"; then
    record PASS "$label" "reversible write/readback/restore verified"
    return 0
  fi
  if [[ "$status" -eq 10 ]]; then
    record SKIP "$label" "no unique safe writable/verifiable target; see $slug.json"
    return 0
  fi
  if [[ "$status" -eq 20 ]]; then
    record FAIL "$label" "write action itself failed before a verified state change"
    return 0
  fi
  abort "$label produced an unverified post-write or restoration state (exit $status)."
}

: >"$OUT_DIR/results.tsv"

# Step 1 — environment
begin_step
progress 0 0 1 "Build and safety preflight" "building control and MIDI observers"
echo "Logic Co-Producer — mixer / instruments / effects / routing capability session"
echo "No timed soak or filler is included."
echo "Writes are attempted only when the probe resolves exactly one safe, reversible target."
echo "Ambiguous controls are recorded as SKIP rather than guessed."
echo "Evidence root: $TEST_ROOT"

mkdir -p "$TEST_ROOT"
swift build >"$OUT_DIR/build.log" 2>&1 || abort "Swift build failed."
LAB="$LAB_DIR/.build/debug/logic-lab"
CONTROL="$LAB_DIR/.build/debug/logic-control-probe"
A1CMP="$LAB_DIR/.build/debug/logic-a1-compare"

progress 5 50 1 "Build and safety preflight" "checking Logic and Accessibility"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1 || abort "logic-lab doctor failed."
grep -q 'Logic Pro running: yes' "$OUT_DIR/doctor.log" || abort "Logic Pro is not running."
grep -q 'Accessibility trusted: yes' "$OUT_DIR/doctor.log" || abort "Accessibility permission is unavailable."

if [[ -z "$EXPECTED" ]]; then
  EXPECTED="$(find "$TEST_ROOT" -type f -name 'logic-a1-golden-v2.expected.json' -print -quit 2>/dev/null || true)"
fi
[[ -n "$EXPECTED" && -f "$EXPECTED" ]] || abort "Could not locate logic-a1-golden-v2.expected.json below $TEST_ROOT."
printf "expected_manifest=%s\n" "$EXPECTED" >"$OUT_DIR/paths.txt"
progress 10 100 1 "Build and safety preflight" "environment and test-root paths PASS"
record PASS "environment" "Logic running, Accessibility trusted, golden manifest found"

# Step 2 — authoritative MIDI safety baseline
begin_step
progress 10 0 2 "Authoritative MIDI safety baseline" "capturing complete selected synthetic region — pass 1"
capture_midi "$OUT_DIR/midi-baseline-1.json" "$OUT_DIR/midi-baseline-1.log" || abort "Could not capture the complete corrected 267-row channel-1 fixture."
progress 15 50 2 "Authoritative MIDI safety baseline" "capturing complete selected synthetic region — pass 2"
capture_midi "$OUT_DIR/midi-baseline-2.json" "$OUT_DIR/midi-baseline-2.log" || abort "Second complete MIDI baseline capture failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/midi-baseline-1.json" --run2 "$OUT_DIR/midi-baseline-2.json" --out "$OUT_DIR/midi-baseline-report.json" >"$OUT_DIR/midi-baseline-compare.log" 2>&1 || abort "Golden/repeatability MIDI safety baseline failed."
grep -q 'RESULT=PASS' "$OUT_DIR/midi-baseline-compare.log" || abort "MIDI safety comparator did not PASS."
record PASS "midi-baseline" "exact golden 267-event state confirmed twice"
progress 20 100 2 "Authoritative MIDI safety baseline" "exact golden state PASS"

# Step 3 — actual interactive control inventory
begin_step
progress 20 0 3 "Mixer and channel-strip inventory" "enumerating actual AX controls, values, actions and writability"
"$CONTROL" inventory \
  --queries "Volume,Pan,Mute,Solo,Channel Strip,Instrument,Audio FX,MIDI FX,Plug-in,Send,Input,Output,Stereo Out" \
  --out "$OUT_DIR/inventory/mixer-channel-strip.json" >"$OUT_DIR/inventory/mixer-channel-strip.log" 2>&1 || abort "Interactive mixer/channel-strip inventory failed."
record PASS "control-inventory" "actual matching elements, values, actions and AXValue writability captured"
progress 30 100 3 "Mixer and channel-strip inventory" "interactive control inventory captured"

# Step 4 — substantive safe mixer writes
begin_step
progress 30 0 4 "Mixer reversible write qualification" "volume: unique-target write → rescan → restore"
run_roundtrip numeric-roundtrip "Volume" volume "mixer-volume"
progress 37 25 4 "Mixer reversible write qualification" "pan: unique-target write → rescan → restore"
run_roundtrip numeric-roundtrip "Pan" pan "mixer-pan"
progress 44 50 4 "Mixer reversible write qualification" "mute: toggle → independent rescan → restore"
run_roundtrip press-roundtrip "Mute" mute "mixer-mute"
progress 51 75 4 "Mixer reversible write qualification" "solo: toggle → independent rescan → restore"
run_roundtrip press-roundtrip "Solo" solo "mixer-solo"
progress 58 100 4 "Mixer reversible write qualification" "mixer write attempts complete; ambiguity was never guessed"

# Step 5 — instrument/effect capability surface
begin_step
progress 58 0 5 "Instrument and effect capability" "capturing slot identities, actions, values, bypass/preset/parameter surfaces"
"$CONTROL" inventory \
  --queries "Instrument,Software Instrument,Audio FX,MIDI FX,Plug-in,Plugin,Bypass,Preset,Parameter,Controls" \
  --out "$OUT_DIR/inventory/instruments-effects.json" >"$OUT_DIR/inventory/instruments-effects.log" 2>&1 || record FAIL "instrument-effect-inventory" "probe returned non-zero"
if grep -q 'RESULT=PASS' "$OUT_DIR/inventory/instruments-effects.log" 2>/dev/null; then
  record PASS "instrument-effect-inventory" "actual accessible slot/control capability surface captured"
fi
progress 70 100 5 "Instrument and effect capability" "instrument/effect capability evidence captured"

# Step 6 — routing and sends
begin_step
progress 70 0 6 "Routing and send capability" "capturing input/output/send/bus/sidechain control surfaces"
"$CONTROL" inventory \
  --queries "Send,Bus,Input,Output,Side Chain,Sidechain,Pre Fader,Post Fader,Stereo Out" \
  --out "$OUT_DIR/inventory/routing-sends.json" >"$OUT_DIR/inventory/routing-sends.log" 2>&1 || record FAIL "routing-inventory" "probe returned non-zero"
if grep -q 'RESULT=PASS' "$OUT_DIR/inventory/routing-sends.log" 2>/dev/null; then
  record PASS "routing-inventory" "routing/send accessible controls and actions captured"
fi
progress 78 100 6 "Routing and send capability" "routing/send evidence captured"

# Step 7 — automation surface
begin_step
progress 78 0 7 "Automation capability surface" "capturing automation modes, lanes and related actions without changing mode"
"$CONTROL" inventory \
  --queries "Automation,Read,Touch,Latch,Write,Trim,Relative,Volume,Pan" \
  --out "$OUT_DIR/inventory/automation.json" >"$OUT_DIR/inventory/automation.log" 2>&1 || record FAIL "automation-inventory" "probe returned non-zero"
if grep -q 'RESULT=PASS' "$OUT_DIR/inventory/automation.log" 2>/dev/null; then
  record PASS "automation-inventory" "automation-related accessible controls/actions captured"
fi
progress 86 100 7 "Automation capability surface" "automation evidence captured"

# Step 8 — final authoritative state and package
begin_step
progress 86 0 8 "Final restoration proof" "re-reading complete MIDI region after all control probes"
capture_midi "$OUT_DIR/midi-final.json" "$OUT_DIR/midi-final.log" || abort "Final complete MIDI state could not be captured."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/midi-baseline-1.json" --run2 "$OUT_DIR/midi-final.json" --out "$OUT_DIR/midi-final-report.json" >"$OUT_DIR/midi-final-compare.log" 2>&1 || abort "Final Logic MIDI state is not exactly the starting golden state."
grep -q 'RESULT=PASS' "$OUT_DIR/midi-final-compare.log" || abort "Final golden comparator did not PASS."
record PASS "final-midi-state" "exact original golden region verified after every attempted control write"
progress 94 60 8 "Final restoration proof" "building concise session summary and ZIP"

ELAPSED=$((SECONDS - SESSION_START))
{
  echo "Logic Co-Producer control capability validation"
  echo "RESULT=COMPLETE"
  echo "Elapsed: $(fmt_time "$ELAPSED")"
  echo "PASS=$PASS_COUNT"
  echo "SKIP=$SKIP_COUNT"
  echo "FAIL=$FAIL_COUNT"
  echo
  echo "Interpretation rules:"
  echo "- PASS mixer item = one unique real Logic control was changed, independently rescanned, and restored."
  echo "- SKIP mixer item = current AX tree did not expose exactly one safe target; no write was attempted."
  echo "- FAIL mixer item with exit 20 = AX write itself failed before a verified change."
  echo "- Any unverified post-write/restoration state would have aborted the session immediately."
  echo "- Instrument/effect/routing/automation sections are capability inventories, not write qualification yet."
  echo "- No arbitrary sleep/soak phase was used."
} >"$OUT_DIR/SUMMARY.txt"

zip_evidence || abort "Could not create evidence ZIP."
progress 100 100 8 "Final restoration proof" "complete — evidence packaged"

echo
echo "Done."
echo "Evidence ZIP: $ZIP_PATH"
echo "PASS=$PASS_COUNT SKIP=$SKIP_COUNT FAIL=$FAIL_COUNT"
exit 0
