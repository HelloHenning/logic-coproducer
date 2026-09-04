#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

TEST_ROOT="${LOGIC_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-unattended-deep-session}"
ZIP_PATH="${OUT_DIR}.zip"
EXPECTED="${A1_EXPECTED:-}"

if [[ -z "$EXPECTED" ]]; then
  for candidate in \
    "$TEST_ROOT/logic-a1-golden-v2.expected.json" \
    "$TEST_ROOT/logic-a1-golden.expected.json"; do
    if [[ -f "$candidate" ]]; then EXPECTED="$candidate"; break; fi
  done
fi
if [[ -z "$EXPECTED" && -d "$TEST_ROOT" ]]; then
  EXPECTED="$(find "$TEST_ROOT" -type f \( -name 'logic-a1-golden-v2.expected.json' -o -name 'logic-a1-golden.expected.json' \) -print -quit 2>/dev/null || true)"
fi

rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR/a3/fields" "$OUT_DIR/a3/delete-add" "$OUT_DIR/surfaces" "$OUT_DIR/menus" "$OUT_DIR/automation" "$OUT_DIR/routing"
: >"$OUT_DIR/results.tsv"

SESSION_START=$SECONDS
STEP_START=$SECONDS
PASS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
CRITICAL=0
LAB=""
A1CMP=""
BLIND=""
ACTOR=""
SURFACE=""
CONTROL=""

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
  if (( overall > 4 )); then eta="~$(fmt_time $((elapsed * (100 - overall) / overall)))"; fi
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
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1));;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1));;
  esac
}

zip_evidence() {
  (
    cd "$(dirname "$OUT_DIR")" || return 1
    /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
  )
}

write_summary() {
  local result="$1" reason="${2:-}"
  {
    echo "Logic Co-Producer unattended deep validation session"
    echo "RESULT=$result"
    [[ -n "$reason" ]] && echo "Reason: $reason"
    echo "PASS=$PASS_COUNT"
    echo "SKIP=$SKIP_COUNT"
    echo "FAIL=$FAIL_COUNT"
    echo "Elapsed: $(fmt_time $((SECONDS - SESSION_START)))"
    echo "No timed soak or filler waits were used."
    echo "User checkpoints during run: 0"
  } >"$OUT_DIR/SUMMARY.txt"
}

abort() {
  local message="$1"
  CRITICAL=1
  echo "CRITICAL FAIL: $message" >&2
  write_summary "CRITICAL_FAIL" "$message"
  zip_evidence >/dev/null 2>&1 || true
  echo "Partial evidence: $ZIP_PATH" >&2
  exit 1
}

capture() {
  local path="$1" log="$2"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$path" >"$log" 2>&1 || return 1
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$log" || return 1
  grep -q 'rows_with_position=267 of 267' "$log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$log" || return 1
}

assert_equal() {
  local pre="$1" post="$2" log="$3"
  "$BLIND" assert-equal --pre "$pre" --post "$post" >"$log" 2>&1
}

blind_compare_verify() {
  local pre="$1" post="$2" plan="$3" diff="$4" log="$5"
  "$BLIND" compare --pre "$pre" --post "$post" --out "$diff" >"$log" 2>&1 || return 1
  "$BLIND" verify --diff "$diff" --plan "$plan" >>"$log" 2>&1
}

recover_or_abort_baseline() {
  local reference="$1" label="$2"
  local current="$OUT_DIR/recovery-current.json" current_log="$OUT_DIR/recovery-current.log" eq_log="$OUT_DIR/recovery-equal.log"
  capture "$current" "$current_log" || abort "$label left the Event List unreadable; manual recovery may be required."
  assert_equal "$reference" "$current" "$eq_log" || abort "$label left Logic different from the protected baseline; refusing further mutation."
}

run_field_case() {
  local id="$1" row_index="$2" field="$3" mode="$4" value="$5" index="$6" count="$7"
  local dir="$OUT_DIR/a3/fields/$id"
  mkdir -p "$dir"
  local base_pct=$(((index - 1) * 100 / count))
  local done_pct=$((index * 100 / count))
  local overall=$((18 + base_pct * 35 / 100))

  progress "$overall" "$base_pct" 3 "A3 isolated external-edit matrix" "$id: authoritative pre-state"
  capture "$dir/pre.json" "$dir/pre.log" || abort "$id pre-state capture failed."
  assert_equal "$OUT_DIR/baseline-1.json" "$dir/pre.json" "$dir/pre-vs-baseline.log" || abort "$id did not start from exact golden baseline."

  local actor_args=(mutate-field --baseline "$dir/pre.json" --row-index "$row_index" --field "$field" --label "$id" --plan "$dir/actor-plan.json")
  if [[ "$mode" == "to" ]]; then actor_args+=(--to "$value"); else actor_args+=(--delta "$value"); fi

  progress "$overall" "$base_pct" 3 "A3 isolated external-edit matrix" "$id: separate actor mutates Logic; observer receives no intent"
  "$ACTOR" "${actor_args[@]}" >"$dir/actor.log" 2>&1
  local rc=$?
  if [[ $rc -eq 10 ]]; then
    record SKIP "A3-$id" "actor could not safely expose this write path"
    recover_or_abort_baseline "$dir/pre.json" "A3-$id SKIP"
    return 0
  elif [[ $rc -ne 0 ]]; then
    record FAIL "A3-$id" "external actor failed rc=$rc"
    recover_or_abort_baseline "$dir/pre.json" "A3-$id failure"
    return 0
  fi

  progress "$overall" "$base_pct" 3 "A3 isolated external-edit matrix" "$id: blind observer refresh #1 and exact diff"
  capture "$dir/post-1.json" "$dir/post-1.log" || abort "$id observer refresh failed after mutation."
  local case_ok=1
  blind_compare_verify "$dir/pre.json" "$dir/post-1.json" "$dir/actor-plan.json" "$dir/blind-diff.json" "$dir/blind-diff.log" || case_ok=0

  progress "$overall" "$base_pct" 3 "A3 isolated external-edit matrix" "$id: blind observer refresh #2 for deterministic current state"
  capture "$dir/post-2.json" "$dir/post-2.log" || abort "$id repeat observer refresh failed."
  assert_equal "$dir/post-1.json" "$dir/post-2.json" "$dir/repeatability.log" || case_ok=0

  progress "$overall" "$base_pct" 3 "A3 isolated external-edit matrix" "$id: automatic exact restoration"
  "$ACTOR" restore-field --baseline-current "$dir/post-1.json" --restore-source "$dir/pre.json" --row-index "$row_index" --field "$field" --label "$id-restore" --plan "$dir/restore-plan.json" >"$dir/restore.log" 2>&1
  rc=$?
  [[ $rc -eq 0 ]] || abort "$id restoration failed rc=$rc."
  capture "$dir/restored.json" "$dir/restored.log" || abort "$id restored-state capture failed."
  assert_equal "$dir/pre.json" "$dir/restored.json" "$dir/restored-vs-pre.log" || abort "$id did not restore exactly."

  if [[ $case_ok -eq 1 ]]; then
    record PASS "A3-$id" "blind fresh read detected exact external edit; repeatable; restored"
  else
    record FAIL "A3-$id" "observer diff/repeatability mismatch; restoration still exact"
  fi
  overall=$((18 + done_pct * 35 / 100))
  progress "$overall" "$done_pct" 3 "A3 isolated external-edit matrix" "$id complete"
}

# -----------------------------------------------------------------------------
# Step 1 — build + environment
# -----------------------------------------------------------------------------
begin_step
progress 0 0 1 "Build and safety preflight" "building all executables once"
echo "Logic Co-Producer — unattended deep validation session"
echo "No manual checkpoint occurs during this run."
echo "After this command starts successfully, do not touch Logic until it finishes."
echo "There are no filler waits or minimum runtime."
echo "Evidence: $OUT_DIR"

swift build >"$OUT_DIR/build.log" 2>&1 || abort "Swift build failed."
LAB="$LAB_DIR/.build/debug/logic-lab"
A1CMP="$LAB_DIR/.build/debug/logic-a1-compare"
BLIND="$LAB_DIR/.build/debug/logic-blind-diff"
ACTOR="$LAB_DIR/.build/debug/logic-external-midi-actor"
SURFACE="$LAB_DIR/.build/debug/logic-surface-explorer"
CONTROL="$LAB_DIR/.build/debug/logic-control-probe"

progress 5 50 1 "Build and safety preflight" "checking Logic, Accessibility, and golden manifest"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1 || abort "logic-lab doctor failed."
grep -q 'Logic Pro running: yes' "$OUT_DIR/doctor.log" || abort "Logic Pro is not running."
grep -q 'Accessibility trusted: yes' "$OUT_DIR/doctor.log" || abort "Accessibility permission is unavailable."
[[ -n "$EXPECTED" && -f "$EXPECTED" ]] || abort "Golden manifest could not be found under $TEST_ROOT."
printf "test_root=%s\nexpected=%s\nout=%s\n" "$TEST_ROOT" "$EXPECTED" "$OUT_DIR" >"$OUT_DIR/paths.txt"
progress 8 100 1 "Build and safety preflight" "environment PASS"
record PASS "preflight" "Logic running, Accessibility trusted, golden manifest found"

# -----------------------------------------------------------------------------
# Step 2 — exact protected baseline
# -----------------------------------------------------------------------------
begin_step
progress 8 0 2 "Protected golden baseline" "complete Event List capture #1"
capture "$OUT_DIR/baseline-1.json" "$OUT_DIR/baseline-1.log" || abort "Baseline capture 1 failed. Keep the qualified synthetic region selected and Event List visible."
progress 12 50 2 "Protected golden baseline" "complete Event List capture #2"
capture "$OUT_DIR/baseline-2.json" "$OUT_DIR/baseline-2.log" || abort "Baseline capture 2 failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/baseline-1.json" --run2 "$OUT_DIR/baseline-2.json" --out "$OUT_DIR/baseline-golden-report.json" >"$OUT_DIR/baseline-golden.log" 2>&1 || abort "Golden/repeatability baseline did not PASS."
grep -q 'RESULT=PASS' "$OUT_DIR/baseline-golden.log" || abort "Golden comparator did not PASS."
record PASS "golden-baseline" "267-event exact state + repeatability"
progress 18 100 2 "Protected golden baseline" "exact 267-event fixture protected"

# -----------------------------------------------------------------------------
# Step 3 — A3 external-edit detection: move, resize, velocity, non-note value
# -----------------------------------------------------------------------------
begin_step
FIELD_CASES=(
  "move-note|6|position|to|1 1 3 81"
  "resize-note|8|length|to|0 0 1 1"
  "velocity|9|value|delta|1"
  "pitch-bend-value|3|value|delta|1"
)
FIELD_COUNT=${#FIELD_CASES[@]}
FIELD_INDEX=0
for spec in "${FIELD_CASES[@]}"; do
  FIELD_INDEX=$((FIELD_INDEX + 1))
  IFS='|' read -r id row_index field mode value <<<"$spec"
  run_field_case "$id" "$row_index" "$field" "$mode" "$value" "$FIELD_INDEX" "$FIELD_COUNT"
done
progress 53 100 3 "A3 isolated external-edit matrix" "field-edit matrix finished; unsupported fields were skipped rather than guessed"

# -----------------------------------------------------------------------------
# Step 4 — A3 delete + add transition via independent Delete then Undo
# -----------------------------------------------------------------------------
begin_step
D="$OUT_DIR/a3/delete-add"
progress 53 0 4 "A3 delete/add detection" "capturing protected pre-delete state"
capture "$D/pre.json" "$D/pre.log" || abort "Delete/add pre-state capture failed."
assert_equal "$OUT_DIR/baseline-1.json" "$D/pre.json" "$D/pre-vs-baseline.log" || abort "Delete/add did not start from exact baseline."

progress 55 15 4 "A3 delete/add detection" "external actor selects one qualified note and presses Delete"
"$ACTOR" delete-row --baseline "$D/pre.json" --row-index 11 --label "delete-note" --plan "$D/delete-plan.json" >"$D/delete-actor.log" 2>&1
rc=$?
if [[ $rc -eq 10 ]]; then
  record SKIP "A3-delete-add" "row selection/delete could not be verified safely"
  recover_or_abort_baseline "$D/pre.json" "A3 delete SKIP"
elif [[ $rc -ne 0 ]]; then
  record FAIL "A3-delete" "external delete actor failed rc=$rc"
  recover_or_abort_baseline "$D/pre.json" "A3 delete failure"
else
  local_ok=1
  progress 58 35 4 "A3 delete/add detection" "blind observer detects one removal"
  # Deletion has 266 rows, so use direct event-list capture without the 267-row guard.
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$D/deleted-1.json" >"$D/deleted-1.log" 2>&1 || abort "Observer could not capture deleted state."
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$D/deleted-1.log" || abort "Deleted-state hydration was incomplete."
  blind_compare_verify "$D/pre.json" "$D/deleted-1.json" "$D/delete-plan.json" "$D/delete-blind-diff.json" "$D/delete-blind-diff.log" || local_ok=0

  progress 61 50 4 "A3 delete/add detection" "repeat blind refresh of deleted state"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$D/deleted-2.json" >"$D/deleted-2.log" 2>&1 || abort "Repeat deleted-state capture failed."
  assert_equal "$D/deleted-1.json" "$D/deleted-2.json" "$D/delete-repeatability.log" || local_ok=0

  progress 64 70 4 "A3 delete/add detection" "external actor invokes Undo; observer treats returned note as an independent add transition"
  "$ACTOR" undo-delete --deleted-state "$D/deleted-1.json" --original-state "$D/pre.json" --row-index 11 --label "add-note-via-undo" --plan "$D/add-plan.json" >"$D/add-actor.log" 2>&1
  rc=$?
  [[ $rc -eq 0 ]] || abort "Delete restoration/Undo failed rc=$rc."
  capture "$D/restored-1.json" "$D/restored-1.log" || abort "Observer could not capture post-Undo state."
  blind_compare_verify "$D/deleted-1.json" "$D/restored-1.json" "$D/add-plan.json" "$D/add-blind-diff.json" "$D/add-blind-diff.log" || local_ok=0
  assert_equal "$D/pre.json" "$D/restored-1.json" "$D/final-vs-pre.log" || abort "Delete/add cycle did not restore exactly."

  progress 67 100 4 "A3 delete/add detection" "delete/add observer cycle complete and exact restoration proved"
  if [[ $local_ok -eq 1 ]]; then
    record PASS "A3-delete" "blind observer detected exactly one removed event"
    record PASS "A3-add" "blind observer detected exactly one added event after external Undo"
  else
    record FAIL "A3-delete-add" "observer diff mismatch; restoration exact"
  fi
fi

# -----------------------------------------------------------------------------
# Step 5 — deep surface + CoreMIDI inventories (read-only)
# -----------------------------------------------------------------------------
begin_step
progress 67 0 5 "Cross-domain capability inventory" "capturing mixer/Inspector/plugin/routing/automation surface without changing project state"
"$SURFACE" deep-inventory --out "$OUT_DIR/surfaces/deep-inventory.json" >"$OUT_DIR/surfaces/deep-inventory.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then record PASS "surface-deep-inventory" "AX surface captured"; else record FAIL "surface-deep-inventory" "rc=$rc"; fi

progress 70 50 5 "Cross-domain capability inventory" "enumerating CoreMIDI endpoints for A4 MCU readiness"
"$SURFACE" midi-endpoints --out "$OUT_DIR/surfaces/midi-endpoints.json" >"$OUT_DIR/surfaces/midi-endpoints.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then record PASS "coremidi-endpoints" "sources/destinations enumerated"; else record FAIL "coremidi-endpoints" "rc=$rc"; fi
progress 73 100 5 "Cross-domain capability inventory" "read-only surface inventories complete"

# -----------------------------------------------------------------------------
# Step 6 — safe menu topology discovery for plug-ins and routing
# -----------------------------------------------------------------------------
begin_step
KINDS=(plugin send output)
KCOUNT=${#KINDS[@]}
KINDEX=0
for kind in "${KINDS[@]}"; do
  KINDEX=$((KINDEX + 1))
  pct=$(((KINDEX - 1) * 100 / KCOUNT))
  overall=$((73 + pct * 10 / 100))
  progress "$overall" "$pct" 6 "Safe plug-in/routing menu discovery" "opening $kind menu only long enough to enumerate choices, then Escape"
  "$SURFACE" menu-inventory --kind "$kind" --out "$OUT_DIR/menus/$kind.json" >"$OUT_DIR/menus/$kind.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    record PASS "menu-$kind" "menu opened, enumerated, closed without selection"
  elif [[ $rc -eq 10 ]]; then
    record SKIP "menu-$kind" "safe unique menu target unavailable"
  else
    record FAIL "menu-$kind" "rc=$rc"
  fi
done
progress 83 100 6 "Safe plug-in/routing menu discovery" "menu topology evidence captured without choosing any project-changing item"

# -----------------------------------------------------------------------------
# Step 7 — automation view probe + one unambiguous input-gain round-trip
# -----------------------------------------------------------------------------
begin_step
progress 83 0 7 "Automation and input-control qualification" "toggling Automation view, inventorying exposed controls, then restoring view"
"$SURFACE" automation-toggle --out "$OUT_DIR/automation/view-toggle.json" >"$OUT_DIR/automation/view-toggle.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  record PASS "automation-view-toggle" "view toggled and restored; exposed automation controls captured"
elif [[ $rc -eq 10 ]]; then
  record SKIP "automation-view-toggle" "unique safe automation view toggle unavailable"
elif [[ $rc -eq 30 ]]; then
  abort "Automation view could not be verified restored."
else
  record FAIL "automation-view-toggle" "rc=$rc"
fi

progress 87 55 7 "Automation and input-control qualification" "testing the unique selected-channel input gain if safely writable"
"$CONTROL" numeric-roundtrip --query "input gain" --out "$OUT_DIR/routing/input-gain-roundtrip.json" >"$OUT_DIR/routing/input-gain-roundtrip.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  record PASS "input-gain-roundtrip" "changed, independently rescanned, restored"
elif [[ $rc -eq 10 ]]; then
  record SKIP "input-gain-roundtrip" "no unique safe writable input-gain target"
elif [[ $rc -eq 30 ]]; then
  abort "Input-gain control could not be verified restored."
else
  record FAIL "input-gain-roundtrip" "rc=$rc"
fi
progress 90 100 7 "Automation and input-control qualification" "non-MIDI reversible/control probes complete"

# -----------------------------------------------------------------------------
# Step 8 — final golden verification + package
# -----------------------------------------------------------------------------
begin_step
progress 90 0 8 "Final protected-state verification" "complete Event List read after every automated action"
capture "$OUT_DIR/final-1.json" "$OUT_DIR/final-1.log" || abort "Final complete-state capture failed."
assert_equal "$OUT_DIR/baseline-1.json" "$OUT_DIR/final-1.json" "$OUT_DIR/final-vs-baseline.log" || abort "Final Logic MIDI state differs from protected baseline."

progress 94 40 8 "Final protected-state verification" "second final read for repeatability"
capture "$OUT_DIR/final-2.json" "$OUT_DIR/final-2.log" || abort "Final repeat capture failed."
"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/final-1.json" --run2 "$OUT_DIR/final-2.json" --out "$OUT_DIR/final-golden-report.json" >"$OUT_DIR/final-golden.log" 2>&1 || abort "Final golden comparison failed."
grep -q 'RESULT=PASS' "$OUT_DIR/final-golden.log" || abort "Final golden comparator did not PASS."
record PASS "final-golden" "267-event state exact after all automated work"

progress 97 75 8 "Final protected-state verification" "writing summary and packaging one ZIP"
if (( FAIL_COUNT > 0 )); then final_result="PARTIAL"; else final_result="PASS"; fi
write_summary "$final_result"
zip_evidence || abort "Could not package evidence ZIP."
progress 100 100 8 "Final protected-state verification" "finished — Logic returned to protected golden state"

echo
echo "============================================================"
echo "UNATTENDED SESSION COMPLETE"
echo "============================================================"
echo "Result: $final_result | PASS=$PASS_COUNT SKIP=$SKIP_COUNT FAIL=$FAIL_COUNT"
echo "Elapsed: $(fmt_time $((SECONDS - SESSION_START)))"
echo "ZIP: $ZIP_PATH"
echo "No further action is required until you choose to upload that ZIP."
