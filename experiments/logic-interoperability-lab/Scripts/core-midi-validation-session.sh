#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

EXPECTED="${A1_EXPECTED:-$HOME/Desktop/logic-a1-golden-v2.expected.json}"
OUT_DIR="${1:-$HOME/Desktop/coproducer-core-midi-session}"
ZIP_PATH="${OUT_DIR}.zip"
rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR/a3" "$OUT_DIR/a2"

SESSION_START=$SECONDS
STEP_START=$SECONDS
MUTATED=0
RESTORE_POSITION=""
RESTORE_CHANNEL="1"
RESTORE_FROM=""
RESTORE_TO=""
RESTORE_VELOCITY=""
LAB=""
MUT=""
CMP=""
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
  if (( overall > 2 )); then
    eta="~$(fmt_time $((elapsed * (100 - overall) / overall)))"
  fi
  echo
  printf "Overall  [%s] %3d%%   Step %s of 6\n" "$(bar "$overall")" "$overall" "$step_no"
  printf "Current  [%s] %3d%%   %s\n" "$(bar "$current")" "$current" "$step_name"
  printf "Action:   %s\n" "$detail"
  printf "Elapsed overall: %s | current step: %s | ETA: %s\n" "$(fmt_time "$elapsed")" "$(fmt_time "$step_elapsed")" "$eta"
}

begin_step() {
  STEP_START=$SECONDS
}

capture() {
  local path="$1" log="$2"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$path" >"$log" 2>&1 || return 1
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$log" || return 1
  grep -q 'rows_with_position=267 of 267' "$log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$log" || return 1
}

zip_evidence() {
  (
    cd "$(dirname "$OUT_DIR")" || return 1
    /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
  )
}

attempt_restore() {
  if [[ "$MUTATED" -ne 1 || -z "$MUT" || -z "$RESTORE_FROM" || -z "$RESTORE_TO" ]]; then
    return 0
  fi
  echo "Attempting automatic emergency restoration..." >&2
  "$MUT" \
    --position "$RESTORE_POSITION" \
    --channel "$RESTORE_CHANNEL" \
    --velocity "$RESTORE_VELOCITY" \
    --from "$RESTORE_FROM" \
    --to "$RESTORE_TO" \
    >"$OUT_DIR/emergency-restore.log" 2>&1 || true
  MUTATED=0
}

abort() {
  local message="$1"
  echo "FAIL: $message" >&2
  attempt_restore
  {
    echo "Logic Co-Producer core MIDI validation session"
    echo "RESULT=FAIL"
    echo "Reason: $message"
    echo "Elapsed: $(fmt_time $((SECONDS - SESSION_START)))"
  } >"$OUT_DIR/SUMMARY.txt"
  zip_evidence >/dev/null 2>&1 || true
  echo "Partial evidence: $ZIP_PATH" >&2
  exit 1
}

on_signal() {
  attempt_restore
  exit 130
}
trap on_signal INT TERM

compare_mutation() {
  local pre="$1" post="$2" position="$3" channel="$4" from="$5" to="$6" velocity="$7" log="$8"
  "$CMP" --pre "$pre" --post "$post" --mode mutation \
    --position "$position" --channel "$channel" --from "$from" --to "$to" --velocity "$velocity" \
    >"$log" 2>&1
}

compare_equal() {
  local a="$1" b="$2" log="$3"
  "$CMP" --pre "$a" --post "$b" --mode restore >"$log" 2>&1
}

run_pitch_case() {
  local case_id="$1" position="$2" from="$3" to="$4" velocity="$5" case_index="$6" case_count="$7"
  local dir="$OUT_DIR/a2/$case_id"
  mkdir -p "$dir"
  local base_pct=$(((case_index - 1) * 100 / case_count))
  local done_pct=$((case_index * 100 / case_count))
  local overall=$((40 + base_pct * 52 / 100))

  progress "$overall" "$base_pct" 5 "A2 granular mutation matrix" "case $case_index/$case_count: complete pre-state capture at $position"
  capture "$dir/pre.json" "$dir/pre.log" || abort "A2 $case_id could not capture a complete pre-state."
  compare_equal "$OUT_DIR/baseline-1.json" "$dir/pre.json" "$dir/pre-vs-baseline.log" || abort "A2 $case_id did not begin from the exact golden baseline."

  progress "$overall" "$base_pct" 5 "A2 granular mutation matrix" "case $case_index/$case_count: writing pitch $from -> $to"
  "$MUT" --position "$position" --channel 1 --velocity "$velocity" --from "$from" --to "$to" >"$dir/mutate.log" 2>&1 || abort "A2 $case_id write failed."
  grep -q 'RESULT=WRITE_OK' "$dir/mutate.log" || abort "A2 $case_id immediate write readback failed."
  MUTATED=1
  RESTORE_POSITION="$position"
  RESTORE_CHANNEL="1"
  RESTORE_FROM="$to"
  RESTORE_TO="$from"
  RESTORE_VELOCITY="$velocity"

  progress "$overall" "$base_pct" 5 "A2 granular mutation matrix" "case $case_index/$case_count: full-region collateral readback"
  capture "$dir/post.json" "$dir/post.log" || abort "A2 $case_id could not capture post-mutation state."
  compare_mutation "$dir/pre.json" "$dir/post.json" "$position" 1 "$from" "$to" "$velocity" "$dir/mutation-diff.log" || abort "A2 $case_id changed more or less than the intended pitch field."

  progress "$overall" "$base_pct" 5 "A2 granular mutation matrix" "case $case_index/$case_count: restoring and independently verifying"
  "$MUT" --position "$position" --channel 1 --velocity "$velocity" --from "$to" --to "$from" >"$dir/restore.log" 2>&1 || abort "A2 $case_id restoration write failed."
  grep -q 'RESULT=WRITE_OK' "$dir/restore.log" || abort "A2 $case_id restoration did not read back immediately."
  MUTATED=0
  capture "$dir/restored.json" "$dir/restored.log" || abort "A2 $case_id could not capture restored state."
  compare_equal "$dir/pre.json" "$dir/restored.json" "$dir/restore-diff.log" || abort "A2 $case_id restoration was not exact."

  overall=$((40 + done_pct * 52 / 100))
  progress "$overall" "$done_pct" 5 "A2 granular mutation matrix" "case $case_index/$case_count PASS — exact write, collateral check, restoration"
}

# -----------------------------------------------------------------------------
# Step 1: build and environment
# -----------------------------------------------------------------------------
begin_step
progress 0 0 1 "Build and safety preflight" "building all lab executables once"
echo "Logic Co-Producer — core MIDI validation session"
echo "This session contains only substantive feasibility tests; there is no timed soak or filler wait."
echo "One manual edit checkpoint occurs near the beginning. After that checkpoint, leave Logic untouched until completion."
echo "Evidence: $OUT_DIR"

swift build >"$OUT_DIR/build.log" 2>&1 || abort "Swift build failed."
LAB="$LAB_DIR/.build/debug/logic-lab"
MUT="$LAB_DIR/.build/debug/logic-a2-mutate"
CMP="$LAB_DIR/.build/debug/logic-a2-compare"
A1CMP="$LAB_DIR/.build/debug/logic-a1-compare"

progress 5 50 1 "Build and safety preflight" "checking Logic version and Accessibility permission"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1 || abort "logic-lab doctor failed."
grep -q 'Logic Pro running: yes' "$OUT_DIR/doctor.log" || abort "Logic Pro is not running."
grep -q 'Accessibility trusted: yes' "$OUT_DIR/doctor.log" || abort "Accessibility permission is unavailable."
[[ -f "$EXPECTED" ]] || abort "Golden fixture manifest is missing at $EXPECTED."
progress 10 100 1 "Build and safety preflight" "environment PASS"

# -----------------------------------------------------------------------------
# Step 2: exact baseline, twice
# -----------------------------------------------------------------------------
begin_step
progress 10 0 2 "Exact golden baseline" "capturing complete Event List state — pass 1"
capture "$OUT_DIR/baseline-1.json" "$OUT_DIR/baseline-1.log" || abort "Baseline capture 1 failed. Keep corrected channel-1 fixture selected with Event List visible."
progress 15 50 2 "Exact golden baseline" "capturing complete Event List state — pass 2"
capture "$OUT_DIR/baseline-2.json" "$OUT_DIR/baseline-2.log" || abort "Baseline capture 2 failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/baseline-1.json" --run2 "$OUT_DIR/baseline-2.json" --out "$OUT_DIR/baseline-golden-report.json" >"$OUT_DIR/baseline-golden.log" 2>&1 || abort "Exact golden/repeatability baseline did not PASS."
grep -q 'RESULT=PASS' "$OUT_DIR/baseline-golden.log" || abort "Golden baseline comparator did not PASS."
progress 20 100 2 "Exact golden baseline" "267-event golden state and repeatability PASS"

# -----------------------------------------------------------------------------
# Step 3: one genuine human edit for source-of-truth validation
# -----------------------------------------------------------------------------
begin_step
progress 20 0 3 "Manual source-of-truth checkpoint" "waiting for one direct human edit in Logic"
echo
echo "MANUAL CHECKPOINT — this is the only action you need to perform during the session."
echo "In the visible Event List, find the Note row at Position 1 1 1 1 (immediately below the Program row)."
echo "Its Num value is C♯3 / MIDI 61 and velocity is 20."
echo "Directly edit ONLY that Num value from C♯3 (61) to D3 (62)."
echo "Do not change anything else."
echo
echo "When Logic shows D3 / 62 for that row, return to Terminal and press Return."
echo "After pressing Return, leave Logic and this Mac untouched until the session finishes."
read -r _
MUTATED=1
RESTORE_POSITION="1 1 1 1"
RESTORE_CHANNEL="1"
RESTORE_FROM="62"
RESTORE_TO="61"
RESTORE_VELOCITY="20"
progress 25 100 3 "Manual source-of-truth checkpoint" "manual edit declared complete; automatic validation begins"

# -----------------------------------------------------------------------------
# Step 4: prove refresh sees the human edit, then restore it
# -----------------------------------------------------------------------------
begin_step
progress 25 0 4 "A3 manual-change detection" "refreshing authoritative state without using prior mutation intent"
capture "$OUT_DIR/a3/manual-post-1.json" "$OUT_DIR/a3/manual-post-1.log" || abort "A3 could not refresh after the manual edit."
compare_mutation "$OUT_DIR/baseline-1.json" "$OUT_DIR/a3/manual-post-1.json" "1 1 1 1" 1 61 62 20 "$OUT_DIR/a3/manual-diff.log" || abort "A3 did not observe exactly the requested human pitch edit."
progress 30 35 4 "A3 manual-change detection" "re-reading the edited Logic state to test deterministic refresh"
capture "$OUT_DIR/a3/manual-post-2.json" "$OUT_DIR/a3/manual-post-2.log" || abort "A3 repeat refresh failed."
compare_equal "$OUT_DIR/a3/manual-post-1.json" "$OUT_DIR/a3/manual-post-2.json" "$OUT_DIR/a3/repeatability.log" || abort "A3 repeat refresh was not deterministic."
progress 35 70 4 "A3 manual-change detection" "restoring the human edit through the qualified writer"
"$MUT" --position "1 1 1 1" --channel 1 --velocity 20 --from 62 --to 61 >"$OUT_DIR/a3/restore.log" 2>&1 || abort "A3 automatic restoration failed."
grep -q 'RESULT=WRITE_OK' "$OUT_DIR/a3/restore.log" || abort "A3 restoration did not read back immediately."
MUTATED=0
capture "$OUT_DIR/a3/restored.json" "$OUT_DIR/a3/restored.log" || abort "A3 could not capture restored state."
compare_equal "$OUT_DIR/baseline-1.json" "$OUT_DIR/a3/restored.json" "$OUT_DIR/a3/restored-vs-baseline.log" || abort "A3 did not restore exactly to baseline."
progress 40 100 4 "A3 manual-change detection" "human edit detected, repeat refresh deterministic, exact restoration PASS"

# -----------------------------------------------------------------------------
# Step 5: representative A2 matrix across visible + deeply offscreen positions
# -----------------------------------------------------------------------------
begin_step
CASES=(
  "start|1 1 1 1|61|62|20"
  "early|4 1 3 1|64|65|48"
  "quarter|8 4 3 8|72|73|56"
  "middle|16 3 3 1|80|81|52"
  "late|29 1 3 1|48|49|56"
  "end|32 4 3 1|72|73|68"
)
CASE_COUNT=${#CASES[@]}
CASE_INDEX=0
for spec in "${CASES[@]}"; do
  CASE_INDEX=$((CASE_INDEX + 1))
  IFS='|' read -r case_id position from to velocity <<<"$spec"
  run_pitch_case "$case_id" "$position" "$from" "$to" "$velocity" "$CASE_INDEX" "$CASE_COUNT"
done
progress 92 100 5 "A2 granular mutation matrix" "all $CASE_COUNT representative visible/offscreen mutation cases PASS"

# -----------------------------------------------------------------------------
# Step 6: final authoritative state + package
# -----------------------------------------------------------------------------
begin_step
progress 92 0 6 "Final golden verification" "capturing final complete state after every write/restore cycle"
capture "$OUT_DIR/final.json" "$OUT_DIR/final.log" || abort "Final complete-state capture failed."
compare_equal "$OUT_DIR/baseline-1.json" "$OUT_DIR/final.json" "$OUT_DIR/final-vs-baseline.log" || abort "Final Logic state differs from the starting baseline."
progress 96 50 6 "Final golden verification" "rechecking final state against the synthetic golden fixture"
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/baseline-1.json" --run2 "$OUT_DIR/final.json" --out "$OUT_DIR/final-golden-report.json" >"$OUT_DIR/final-golden.log" 2>&1 || abort "Final golden comparison failed."
grep -q 'RESULT=PASS' "$OUT_DIR/final-golden.log" || abort "Final golden comparator did not PASS."

ELAPSED=$((SECONDS - SESSION_START))
cat >"$OUT_DIR/SUMMARY.txt" <<EOF
Logic Co-Producer core MIDI validation session
Elapsed: $(fmt_time "$ELAPSED")
No artificial soak/wait phase: yes
A1 exact golden baseline: PASS
A3 direct human pitch edit detected by fresh authoritative read: PASS
A3 repeated refresh deterministic: PASS
A3 exact restoration: PASS
A2 representative pitch mutation cases: $CASE_COUNT PASS
A2 full-region collateral verification after each mutation: PASS
A2 exact restoration after each mutation: PASS
Final state equals starting golden state: PASS
RESULT=PASS
EOF

progress 99 90 6 "Final golden verification" "packaging one sanitized evidence ZIP"
zip_evidence || abort "Could not create evidence ZIP."
progress 100 100 6 "Final golden verification" "complete"
trap - INT TERM
printf '\a'
echo
echo "CORE MIDI SESSION RESULT=PASS"
printf "Runtime: %s\n" "$(fmt_time "$ELAPSED")"
echo "Evidence ZIP: $ZIP_PATH"
echo "Upload only that ZIP; Terminal output is not needed if RESULT=PASS."
