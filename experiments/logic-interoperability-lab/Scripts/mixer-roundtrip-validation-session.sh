#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

TEST_ROOT="${LOGIC_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-mixer-roundtrip-session}"
ZIP_PATH="${OUT_DIR}.zip"
EXPECTED="${A1_EXPECTED:-}"

rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR/matrix"

SESSION_START=$SECONDS
STEP_START=$SECONDS
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
LAB=""
MATRIX=""
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
  if (( overall > 3 )); then eta="~$(fmt_time $((elapsed * (100 - overall) / overall)))"; fi
  echo
  printf "Overall  [%s] %3d%%   Step %s of 8\n" "$(bar "$overall")" "$overall" "$step_no"
  printf "Current  [%s] %3d%%   %s\n" "$(bar "$current")" "$current" "$step_name"
  printf "Action:   %s\n" "$detail"
  printf "Elapsed overall: %s | current step: %s | ETA: %s\n" "$(fmt_time "$elapsed")" "$(fmt_time "$step_elapsed")" "$eta"
}

begin_step() { STEP_START=$SECONDS; }

record() {
  local kind="$1" label="$2" detail="$3"
  printf "%s\t%s\t%s\n" "$kind" "$label" "$detail" >>"$OUT_DIR/results.tsv"
  case "$kind" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1));;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1));;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1));;
  esac
}

zip_evidence() {
  (
    cd "$(dirname "$OUT_DIR")" || return 1
    /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
  )
}

abort() {
  local message="$1"
  echo "FAIL: $message" >&2
  {
    echo "Logic Co-Producer mixer round-trip validation"
    echo "RESULT=FAIL"
    echo "Reason: $message"
    echo "Elapsed: $(fmt_time $((SECONDS - SESSION_START)))"
    echo "PASS=$PASS_COUNT"
    echo "FAIL=$FAIL_COUNT"
    echo "SKIP=$SKIP_COUNT"
  } >"$OUT_DIR/SUMMARY.txt"
  zip_evidence >/dev/null 2>&1 || true
  echo "Partial evidence: $ZIP_PATH" >&2
  exit 1
}

find_expected() {
  if [[ -n "$EXPECTED" && -f "$EXPECTED" ]]; then return 0; fi
  EXPECTED="$(find "$TEST_ROOT" -type f -name 'logic-a1-golden-v2.expected.json' -print 2>/dev/null | sort | head -n 1)"
  [[ -n "$EXPECTED" && -f "$EXPECTED" ]]
}

capture() {
  local path="$1" log="$2"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$path" >"$log" 2>&1 || return 1
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$log" || return 1
  grep -q 'rows_with_position=267 of 267' "$log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$log" || return 1
}

run_matrix() {
  local kind="$1" step_no="$2" overall_start="$3" overall_end="$4"
  local lower
  lower="$(printf '%s' "$kind" | tr '[:upper:]' '[:lower:]')"
  begin_step
  progress "$overall_start" 0 "$step_no" "$kind mixer round-trips" "discovering every visible enabled mixer $kind control"
  set +e
  "$MATRIX" matrix --control "$kind" --out "$OUT_DIR/matrix/$lower.json" 2>&1 | tee "$OUT_DIR/matrix/$lower.log"
  local rc=${PIPESTATUS[0]}
  set -u
  if [[ "$rc" -eq 30 ]] || grep -q 'RESULT=RESTORE_FAIL' "$OUT_DIR/matrix/$lower.log"; then
    abort "$kind matrix changed Logic state but could not prove exact restoration. Stop using this project until the evidence is reviewed."
  fi
  if grep -q 'RESULT=PASS' "$OUT_DIR/matrix/$lower.log"; then
    record PASS "mixer-$lower" "all discovered enabled $kind controls changed exactly one step, peer controls stayed unchanged, and exact restoration passed"
  elif grep -q 'RESULT=SKIP' "$OUT_DIR/matrix/$lower.log"; then
    record SKIP "mixer-$lower" "no qualifying enabled mixer $kind controls were exposed"
  else
    record FAIL "mixer-$lower" "one or more $kind cases failed, but every attempted mutation was restored; inspect matrix/$lower.json"
  fi
  progress "$overall_end" 100 "$step_no" "$kind mixer round-trips" "matrix complete; individual cases recorded in matrix/$lower.json"
}

# Step 1 — build and safety preflight
begin_step
progress 0 0 1 "Build and safety preflight" "building qualified observers and the mixer matrix probe"
echo "Logic Co-Producer — substantive mixer round-trip validation"
echo "No timed soak or filler phase is used."
echo "The runner mutates only visible enabled mixer controls in the synthetic fixture, one at a time, and restores each before continuing."
echo "Evidence: $OUT_DIR"

swift build >"$OUT_DIR/build.log" 2>&1 || abort "Swift build failed."
LAB="$LAB_DIR/.build/debug/logic-lab"
MATRIX="$LAB_DIR/.build/debug/logic-mixer-matrix"
A1CMP="$LAB_DIR/.build/debug/logic-a1-compare"
progress 5 45 1 "Build and safety preflight" "checking Logic and Accessibility"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1 || abort "logic-lab doctor failed."
grep -q 'Logic Pro running: yes' "$OUT_DIR/doctor.log" || abort "Logic Pro is not running."
grep -q 'Accessibility trusted: yes' "$OUT_DIR/doctor.log" || abort "Accessibility permission is unavailable."
find_expected || abort "Could not locate logic-a1-golden-v2.expected.json anywhere under $TEST_ROOT."
printf 'expected_manifest=%s\n' "$EXPECTED" >"$OUT_DIR/paths.txt"
record PASS environment "Logic running, Accessibility trusted, golden manifest found"
progress 10 100 1 "Build and safety preflight" "environment PASS"

# Step 2 — prove we are operating on the synthetic MIDI fixture before mixer writes
begin_step
progress 10 0 2 "Synthetic fixture safety baseline" "complete Event List capture 1 of 2"
capture "$OUT_DIR/midi-baseline-1.json" "$OUT_DIR/midi-baseline-1.log" || abort "Synthetic MIDI baseline capture 1 failed. Keep the corrected channel-1 fixture selected and Event List visible."
progress 15 50 2 "Synthetic fixture safety baseline" "complete Event List capture 2 of 2"
capture "$OUT_DIR/midi-baseline-2.json" "$OUT_DIR/midi-baseline-2.log" || abort "Synthetic MIDI baseline capture 2 failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/midi-baseline-1.json" --run2 "$OUT_DIR/midi-baseline-2.json" --out "$OUT_DIR/midi-baseline-report.json" >"$OUT_DIR/midi-baseline-compare.log" 2>&1 || abort "The selected region is not the exact qualified golden fixture. No mixer write was attempted."
grep -q 'RESULT=PASS' "$OUT_DIR/midi-baseline-compare.log" || abort "Golden synthetic-fixture baseline did not PASS."
record PASS synthetic-fixture "exact 267-event golden state confirmed before mixer writes"
progress 20 100 2 "Synthetic fixture safety baseline" "qualified synthetic project context confirmed"

# Step 3 — capture semantic/topological evidence before any mixer write
begin_step
progress 20 0 3 "Mixer strip topology" "enumerating mixer strip groups, labels, selection hints and control paths"
"$MATRIX" topology --out "$OUT_DIR/topology-before.json" >"$OUT_DIR/topology-before.log" 2>&1 || abort "Mixer topology capture failed."
grep -q 'RESULT=PASS' "$OUT_DIR/topology-before.log" || abort "Mixer topology did not complete."
record PASS mixer-topology "actual visible mixer strips and Volume/Pan/Mute/Solo control bindings captured"
progress 28 100 3 "Mixer strip topology" "topology captured; raw control matrix begins"

# Steps 4–7 — substantive reversible raw mixer control tests
run_matrix Volume 4 28 46
run_matrix Pan 5 46 64
run_matrix Mute 6 64 80
run_matrix Solo 7 80 94

# Step 8 — final topology and authoritative MIDI safety verification
begin_step
progress 94 0 8 "Final restoration verification" "rescanning mixer topology after every round-trip"
"$MATRIX" topology --out "$OUT_DIR/topology-after.json" >"$OUT_DIR/topology-after.log" 2>&1 || abort "Final mixer topology capture failed."
progress 96 35 8 "Final restoration verification" "capturing complete MIDI state after mixer testing"
capture "$OUT_DIR/midi-final.json" "$OUT_DIR/midi-final.log" || abort "Final MIDI capture failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/midi-baseline-1.json" --run2 "$OUT_DIR/midi-final.json" --out "$OUT_DIR/midi-final-report.json" >"$OUT_DIR/midi-final-compare.log" 2>&1 || abort "Final MIDI state differs from the original golden state."
grep -q 'RESULT=PASS' "$OUT_DIR/midi-final-compare.log" || abort "Final golden comparison did not PASS."
record PASS final-state "exact original 267-event MIDI state verified after all mixer mutations and restorations"
progress 98 75 8 "Final restoration verification" "packaging one evidence ZIP"

ELAPSED=$((SECONDS - SESSION_START))
{
  echo "Logic Co-Producer mixer round-trip validation"
  echo "RESULT=COMPLETE"
  echo "Elapsed: $(fmt_time "$ELAPSED")"
  echo "PASS=$PASS_COUNT"
  echo "FAIL=$FAIL_COUNT"
  echo "SKIP=$SKIP_COUNT"
  echo
  echo "No timed soak or filler phase was used."
  echo "Each matrix case changed one actual visible enabled mixer control by one adjacent step/toggle, independently rescanned all peer controls, restored the target, and verified the complete peer set returned to pre-case state."
  echo "Topology evidence is separate: it is intended to determine whether raw AX control paths can be bound safely to semantic track/channel-strip identity."
} >"$OUT_DIR/SUMMARY.txt"
zip_evidence || abort "Evidence ZIP creation failed."
progress 100 100 8 "Final restoration verification" "COMPLETE — evidence packaged"
echo
echo "Done."
echo "Elapsed: $(fmt_time "$ELAPSED")"
echo "Evidence ZIP: $ZIP_PATH"
/usr/bin/osascript -e 'display notification "Mixer round-trip validation finished" with title "Logic Co-Producer"' >/dev/null 2>&1 || true
