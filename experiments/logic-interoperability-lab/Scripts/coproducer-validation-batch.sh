#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

OUT_DIR="${1:-$HOME/Desktop/coproducer-validation-batch}"
EXPECTED="${A1_EXPECTED:-$HOME/Desktop/logic-a1-golden-v2.expected.json}"
PREVIOUS_A1_REPORT="${A1_REPORT:-$HOME/Desktop/logic-a1-test/report.json}"
ZIP_PATH="${OUT_DIR}.zip"
TOTAL_STEPS=8
CURRENT_STEP=1
BATCH_START=$SECONDS
STEP_START=$SECONDS
mkdir -p "$OUT_DIR"
rm -f "$ZIP_PATH"

bar() {
  local pct="$1"
  local width=20
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local s=""
  local i
  for ((i=0; i<filled; i++)); do s="${s}█"; done
  for ((i=0; i<empty; i++)); do s="${s}░"; done
  printf "%s" "$s"
}

fmt_time() {
  local t="$1"
  printf "%02dm %02ds" $((t / 60)) $((t % 60))
}

progress() {
  local current_pct="$1"
  local label="$2"
  local detail="$3"
  local overall=$(( ((CURRENT_STEP - 1) * 100 + current_pct) / TOTAL_STEPS ))
  local elapsed=$((SECONDS - BATCH_START))
  local step_elapsed=$((SECONDS - STEP_START))
  local eta="calculating"
  if (( overall > 2 )); then
    local remain=$(( elapsed * (100 - overall) / overall ))
    eta="~$(fmt_time "$remain")"
  fi
  echo
  printf "Overall  [%s] %3d%%   Step %d/%d\n" "$(bar "$overall")" "$overall" "$CURRENT_STEP" "$TOTAL_STEPS"
  printf "Current  [%s] %3d%%   %s\n" "$(bar "$current_pct")" "$current_pct" "$label"
  printf "Action:   %s\n" "$detail"
  printf "Elapsed:  %s overall | %s current step | ETA %s\n" "$(fmt_time "$elapsed")" "$(fmt_time "$step_elapsed")" "$eta"
}

begin_step() {
  CURRENT_STEP="$1"
  STEP_START=$SECONDS
  progress 0 "$2" "starting"
}

fail() {
  echo
  echo "VALIDATION BATCH STOPPED: $1" >&2
  echo "Evidence collected so far remains in: $OUT_DIR" >&2
  exit "${2:-1}"
}

run_find() {
  local query="$1"
  local target="$2"
  "$LAB" find "$query" --depth 20 --max-nodes 50000 >"$target" 2>&1 || true
}

# Step 1 — build and environment
begin_step 1 "Build and environment" 
swift build >"$OUT_DIR/build.log" 2>&1 || fail "Swift build failed. See $OUT_DIR/build.log"
progress 40 "Build and environment" "build complete; checking Logic and Accessibility"
LAB="$LAB_DIR/.build/debug/logic-lab"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1 || fail "logic-lab doctor failed."
grep -q "Logic Pro running: yes" "$OUT_DIR/doctor.log" || fail "Logic Pro is not running."
grep -q "Accessibility trusted: yes" "$OUT_DIR/doctor.log" || fail "Accessibility permission is not available."
progress 75 "Build and environment" "capturing windows and focus context"
"$LAB" windows >"$OUT_DIR/windows.log" 2>&1 || true
"$LAB" focused >"$OUT_DIR/focused.log" 2>&1 || true
progress 100 "Build and environment" "environment captured"

# Step 2 — active fixture preflight
begin_step 2 "Active fixture preflight"
"$LAB" event-list --max-rows 2 >"$OUT_DIR/event-list-preflight.log" 2>&1 || fail "Event List preflight failed."
progress 45 "Active fixture preflight" "checking expected 267-row channel-1 fixture"
grep -q "AXRows=267" "$OUT_DIR/event-list-preflight.log" || fail "The active Event List does not expose 267 rows. Keep the corrected channel-1 fixture region active and Event List visible."
grep -Eq 'ch_desc="1"|ch_raw="1"' "$OUT_DIR/event-list-preflight.log" || fail "The active Event List does not appear to be MIDI channel 1."
progress 100 "Active fixture preflight" "corrected golden fixture context verified"

# Step 3 — reuse or refresh exact A1 evidence
begin_step 3 "Exact MIDI baseline"
if [[ -f "$PREVIOUS_A1_REPORT" ]] && grep -Eq '"result"[[:space:]]*:[[:space:]]*"PASS"' "$PREVIOUS_A1_REPORT"; then
  cp "$PREVIOUS_A1_REPORT" "$OUT_DIR/a1-report-reused.json"
  progress 100 "Exact MIDI baseline" "reused existing corrected-fixture PASS evidence"
else
  progress 10 "Exact MIDI baseline" "no reusable PASS report; running two hydrated captures"
  bash "$SCRIPT_DIR/a1-test.sh" "$EXPECTED" "$OUT_DIR/a1-refresh" >"$OUT_DIR/a1-refresh.log" 2>&1 || fail "Automated A1 exact test failed. See $OUT_DIR/a1-refresh.log"
  grep -q "RESULT=PASS" "$OUT_DIR/a1-refresh.log" || fail "A1 exact comparison did not PASS."
  progress 100 "Exact MIDI baseline" "fresh exact comparison PASS"
fi

# Step 4 — Event List filter/context discovery
begin_step 4 "Event List filter context"
filter_queries=("Notes" "Prog. Change" "Pitch Bend" "Controller" "Aftertouch" "Poly Aftertouch" "Syst. Exclusive" "Additional Info")
idx=0
for query in "${filter_queries[@]}"; do
  idx=$((idx + 1))
  safe="$(echo "$query" | tr ' /.' '___')"
  pct=$((idx * 100 / ${#filter_queries[@]}))
  progress "$pct" "Event List filter context" "inspecting filter control: $query"
  run_find "$query" "$OUT_DIR/filter-${safe}.log"
done
progress 100 "Event List filter context" "all filter-control searches captured"

# Step 5 — repeated structural stability reads
begin_step 5 "Event List stability"
STABILITY_RUNS=8
: >"$OUT_DIR/stability-summary.log"
for ((i=1; i<=STABILITY_RUNS; i++)); do
  pct=$((i * 100 / STABILITY_RUNS))
  progress "$pct" "Event List stability" "read $i of $STABILITY_RUNS"
  f="$OUT_DIR/stability-$i.log"
  "$LAB" event-list --max-rows 1 >"$f" 2>&1 || fail "Event List stability read $i failed."
  rows="$(grep '^AXRows=' "$f" | tail -1 | cut -d= -f2)"
  ch="$(grep '^\[0\]' "$f" | sed -E 's/.*ch_desc="([^"]*)".*/\1/' | head -1)"
  echo "run=$i AXRows=${rows:-unknown} channel=${ch:-unknown}" >>"$OUT_DIR/stability-summary.log"
  [[ "$rows" == "267" ]] || fail "Event List row count changed during stability run $i."
done
progress 100 "Event List stability" "$STABILITY_RUNS consecutive 267-row reads complete"

# Step 6 — deep read-only AX snapshot
begin_step 6 "Deep Logic UI snapshot"
progress 10 "Deep Logic UI snapshot" "capturing up to 50,000 AX nodes; leave Logic untouched"
"$LAB" snapshot --out "$OUT_DIR/logic-ax-snapshot.json" --depth 20 --max-nodes 50000 >"$OUT_DIR/snapshot.log" 2>&1 || fail "AX snapshot failed."
progress 100 "Deep Logic UI snapshot" "deep snapshot captured for offline analysis"

# Step 7 — broader co-producer capability inventory
begin_step 7 "Mixer, instruments, effects and routing survey"
survey_queries=(
  "Track" "Region" "Channel Strip" "Volume" "Pan" "Mute" "Solo"
  "Instrument" "Audio FX" "MIDI FX" "Plug-in" "Send" "Bus" "Output" "Input"
  "Automation" "Read" "Touch" "Latch" "Write" "Stereo Out" "Mixer"
)
: >"$OUT_DIR/semantic-inventory-summary.log"
idx=0
for query in "${survey_queries[@]}"; do
  idx=$((idx + 1))
  safe="$(echo "$query" | tr ' /.' '___')"
  f="$OUT_DIR/survey-${safe}.log"
  run_find "$query" "$f"
  matches="$(grep -Eo 'matches=[0-9]+' "$f" | head -1 | cut -d= -f2)"
  echo "$query: ${matches:-unknown}" >>"$OUT_DIR/semantic-inventory-summary.log"
  pct=$((idx * 100 / ${#survey_queries[@]}))
  progress "$pct" "Mixer, instruments, effects and routing survey" "semantic probe $idx/${#survey_queries[@]}: $query"
done
progress 100 "Mixer, instruments, effects and routing survey" "broader semantic inventory captured"

# Step 8 — package evidence and final report
begin_step 8 "Evidence packaging"
progress 20 "Evidence packaging" "writing compact batch summary"
{
  echo "Logic Co-Producer validation batch"
  echo "Completed: $(date)"
  echo "Mode: read-only project-data validation"
  echo
  echo "Preflight: corrected channel-1 golden fixture = PASS"
  if [[ -f "$OUT_DIR/a1-report-reused.json" ]]; then
    echo "A1 exact baseline: reused prior PASS report"
  else
    echo "A1 exact baseline: fresh PASS"
  fi
  echo "Event List stability: $STABILITY_RUNS/$STABILITY_RUNS reads retained 267 rows"
  echo "Filter/context searches: ${#filter_queries[@]} captured"
  echo "Broader semantic probes: ${#survey_queries[@]} captured"
  echo "Deep AX snapshot: captured"
  echo
  echo "No MIDI, mixer, plug-in, automation, routing, or project data was intentionally modified by this batch."
  echo "The next engineering pass should analyze this evidence before requesting further hands-on testing."
} >"$OUT_DIR/SUMMARY.txt"
progress 55 "Evidence packaging" "creating one ZIP for optional upload"
(
  cd "$(dirname "$OUT_DIR")"
  /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
) || fail "Could not create evidence ZIP."
progress 100 "Evidence packaging" "batch complete"

echo
echo "============================================================"
echo "VALIDATION BATCH COMPLETE"
echo "Overall: 100%"
echo "No further action was required while the batch ran."
echo "Summary:  $OUT_DIR/SUMMARY.txt"
echo "Evidence: $ZIP_PATH"
echo "============================================================"
