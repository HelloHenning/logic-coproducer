#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

OUT_DIR="${1:-$HOME/Desktop/coproducer-long-validation-session}"
ZIP_PATH="${OUT_DIR}.zip"
EXPECTED="${A1_EXPECTED:-$HOME/Desktop/logic-a1-golden-v2.expected.json}"
PREVIOUS_A1_REPORT="${A1_REPORT:-$HOME/Desktop/logic-a1-test/report.json}"
MIN_SESSION_SECONDS="${COPRODUCER_MIN_SESSION_SECONDS:-1800}"
STRUCTURAL_INTERVAL="${COPRODUCER_STRUCTURAL_INTERVAL:-15}"
EXACT_INTERVAL="${COPRODUCER_EXACT_INTERVAL:-300}"
INVENTORY_INTERVAL="${COPRODUCER_INVENTORY_INTERVAL:-600}"

START_EPOCH="$(date +%s)"
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"
BATCH_START=$SECONDS
FAILURES=0
WARNINGS=0
STRUCTURAL_READS=0
STRUCTURAL_FAILURES=0
EXACT_CHECKS=0
EXACT_FAILURES=0
INVENTORY_CHECKS=0

rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR/checkpoints" "$OUT_DIR/inventory"

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

show_progress() {
  local overall_pct="$1"
  local current_pct="$2"
  local step="$3"
  local detail="$4"
  local elapsed=$((SECONDS - BATCH_START))
  local remaining=$((MIN_SESSION_SECONDS - elapsed))
  (( remaining < 0 )) && remaining=0
  echo
  printf "Overall  [%s] %3d%%\n" "$(bar "$overall_pct")" "$overall_pct"
  printf "Current  [%s] %3d%%   %s\n" "$(bar "$current_pct")" "$current_pct" "$step"
  printf "Action:   %s\n" "$detail"
  printf "Elapsed:  %s | minimum session remaining: %s\n" "$(fmt_time "$elapsed")" "$(fmt_time "$remaining")"
}

record_failure() {
  local message="$1"
  FAILURES=$((FAILURES + 1))
  echo "FAIL: $message" >>"$OUT_DIR/failures.log"
}

record_warning() {
  local message="$1"
  WARNINGS=$((WARNINGS + 1))
  echo "WARN: $message" >>"$OUT_DIR/warnings.log"
}

run_inventory_counts() {
  local label="$1"
  local outfile="$2"
  local queries=(
    "Track" "Region" "Channel Strip" "Volume" "Pan" "Mute" "Solo"
    "Instrument" "Audio FX" "MIDI FX" "Plug-in" "Send" "Bus" "Output" "Input"
    "Automation" "Read" "Touch" "Latch" "Write" "Stereo Out" "Mixer"
  )
  : >"$outfile"
  echo "inventory=$label" >>"$outfile"
  local query raw matches
  for query in "${queries[@]}"; do
    raw="$($LAB find "$query" --depth 20 --max-nodes 50000 2>&1 || true)"
    matches="$(echo "$raw" | grep -Eo 'matches=[0-9]+' | head -1 | cut -d= -f2)"
    echo "$query=${matches:-unknown}" >>"$outfile"
  done
  INVENTORY_CHECKS=$((INVENTORY_CHECKS + 1))
}

run_filter_capture() {
  local outfile="$1"
  bash "$SCRIPT_DIR/a1-context.sh" "$OUT_DIR/filter-temp" >"$outfile" 2>&1 || record_warning "Event List filter-context capture returned non-zero."
  rm -rf "$OUT_DIR/filter-temp"
}

run_structural_read() {
  local raw rows pos ch channel
  raw="$($LAB event-list --max-rows 1 2>&1)"
  local status=$?
  STRUCTURAL_READS=$((STRUCTURAL_READS + 1))
  rows="$(echo "$raw" | grep '^AXRows=' | tail -1 | cut -d= -f2)"
  pos="$(echo "$raw" | grep '^rows_with_position=' | tail -1 | sed -E 's/.*=([0-9]+) of ([0-9]+).*/\1\/\2/')"
  ch="$(echo "$raw" | grep '^rows_with_channel=' | tail -1 | sed -E 's/.*=([0-9]+) of ([0-9]+).*/\1\/\2/')"
  channel="$(echo "$raw" | grep '^\[0\]' | sed -E 's/.*ch_desc="([^"]*)".*/\1/' | head -1)"
  printf "%s\tstatus=%d\tAXRows=%s\tposition=%s\tchannelCoverage=%s\tactiveChannel=%s\n" \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$status" "${rows:-unknown}" "${pos:-unknown}" "${ch:-unknown}" "${channel:-unknown}" \
    >>"$OUT_DIR/structural-soak.tsv"
  if [[ "$status" -ne 0 || "$rows" != "267" || "$channel" != "1" ]]; then
    STRUCTURAL_FAILURES=$((STRUCTURAL_FAILURES + 1))
    record_failure "Structural soak read $STRUCTURAL_READS was not the expected 267-row channel-1 context."
  fi
}

run_exact_checkpoint() {
  local index="$1"
  local cpdir="$OUT_DIR/checkpoints/exact-$(printf '%02d' "$index")"
  mkdir -p "$cpdir"
  EXACT_CHECKS=$((EXACT_CHECKS + 1))
  set +e
  bash "$SCRIPT_DIR/a1-test.sh" "$EXPECTED" "$cpdir" >"$cpdir/session.log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -ne 0 ]] || ! grep -q "RESULT=PASS" "$cpdir/session.log"; then
    EXACT_FAILURES=$((EXACT_FAILURES + 1))
    record_failure "Exact A1 checkpoint $index did not PASS."
  fi
}

show_progress 0 0 "Environment and build" "starting unattended validation session"

echo "Logic Co-Producer unattended validation session"
echo "Minimum runtime: $(fmt_time "$MIN_SESSION_SECONDS")"
echo "No human interaction is planned during this run."
echo "Leave Logic and this Mac untouched until completion."
echo "Evidence folder: $OUT_DIR"

swift build >"$OUT_DIR/build.log" 2>&1
if [[ $? -ne 0 ]]; then
  echo "Build failed; cannot continue safely. See $OUT_DIR/build.log" >&2
  exit 2
fi
LAB="$LAB_DIR/.build/debug/logic-lab"
show_progress 3 60 "Environment and build" "build complete; checking Logic and Accessibility"
"$LAB" doctor >"$OUT_DIR/doctor.log" 2>&1
if ! grep -q "Logic Pro running: yes" "$OUT_DIR/doctor.log"; then
  echo "Logic Pro is not running. Open Logic with the corrected fixture and retry." >&2
  exit 3
fi
if ! grep -q "Accessibility trusted: yes" "$OUT_DIR/doctor.log"; then
  echo "Accessibility permission is unavailable. Retry after granting Terminal/logic-lab access." >&2
  exit 4
fi
show_progress 5 100 "Environment and build" "environment verified"

show_progress 5 0 "Golden-fixture preflight" "verifying active Event List context"
"$LAB" event-list --max-rows 2 >"$OUT_DIR/preflight.log" 2>&1
if ! grep -q "AXRows=267" "$OUT_DIR/preflight.log" || ! grep -Eq 'ch_desc="1"|ch_raw="1"' "$OUT_DIR/preflight.log"; then
  echo "The active Event List is not the corrected 267-row channel-1 fixture. Keep that region selected and Event List visible, then retry." >&2
  exit 5
fi
show_progress 8 60 "Golden-fixture preflight" "fixture recognized; capturing filter state"
run_filter_capture "$OUT_DIR/filter-context-start.log"
show_progress 10 100 "Golden-fixture preflight" "fixture and filter context captured"

show_progress 10 0 "Baseline exact comparison" "checking existing evidence or refreshing if needed"
if [[ -f "$PREVIOUS_A1_REPORT" ]] && grep -Eq '"result"[[:space:]]*:[[:space:]]*"PASS"' "$PREVIOUS_A1_REPORT"; then
  cp "$PREVIOUS_A1_REPORT" "$OUT_DIR/a1-baseline-reused.json"
else
  run_exact_checkpoint 0
fi
show_progress 15 100 "Baseline exact comparison" "baseline evidence available"

show_progress 15 0 "Broader capability inventory" "capturing sanitized semantic counts only"
run_inventory_counts "start" "$OUT_DIR/inventory/start.txt"
show_progress 20 100 "Broader capability inventory" "initial mixer/instrument/effect/routing inventory captured"

SOAK_START=$SECONDS
ELAPSED_BEFORE_SOAK=$((SOAK_START - BATCH_START))
SOAK_TARGET=$((MIN_SESSION_SECONDS - ELAPSED_BEFORE_SOAK))
(( SOAK_TARGET < 1 )) && SOAK_TARGET=1
NEXT_EXACT=$((SECONDS + EXACT_INTERVAL))
NEXT_INVENTORY=$((SECONDS + INVENTORY_INTERVAL))
EXACT_INDEX=1
INVENTORY_INDEX=1

: >"$OUT_DIR/structural-soak.tsv"
show_progress 20 0 "Long stability and repeatability soak" "starting repeated Logic-state observations"

while (( SECONDS - BATCH_START < MIN_SESSION_SECONDS )); do
  run_structural_read

  if (( SECONDS >= NEXT_EXACT )); then
    elapsed_soak=$((SECONDS - SOAK_START))
    current_pct=$((elapsed_soak * 100 / SOAK_TARGET))
    (( current_pct > 100 )) && current_pct=100
    overall=$((20 + current_pct * 75 / 100))
    show_progress "$overall" "$current_pct" "Long stability and repeatability soak" "running paired exact golden checkpoint $EXACT_INDEX"
    run_exact_checkpoint "$EXACT_INDEX"
    run_filter_capture "$OUT_DIR/checkpoints/filter-$(printf '%02d' "$EXACT_INDEX").log"
    EXACT_INDEX=$((EXACT_INDEX + 1))
    NEXT_EXACT=$((NEXT_EXACT + EXACT_INTERVAL))
  fi

  if (( SECONDS >= NEXT_INVENTORY )); then
    run_inventory_counts "soak-$INVENTORY_INDEX" "$OUT_DIR/inventory/soak-$(printf '%02d' "$INVENTORY_INDEX").txt"
    INVENTORY_INDEX=$((INVENTORY_INDEX + 1))
    NEXT_INVENTORY=$((NEXT_INVENTORY + INVENTORY_INTERVAL))
  fi

  elapsed_soak=$((SECONDS - SOAK_START))
  current_pct=$((elapsed_soak * 100 / SOAK_TARGET))
  (( current_pct > 100 )) && current_pct=100
  overall=$((20 + current_pct * 75 / 100))
  show_progress "$overall" "$current_pct" "Long stability and repeatability soak" \
    "structural read $STRUCTURAL_READS; exact checkpoints $EXACT_CHECKS; failures $FAILURES"

  remaining=$((MIN_SESSION_SECONDS - (SECONDS - BATCH_START)))
  (( remaining <= 0 )) && break
  sleep_for="$STRUCTURAL_INTERVAL"
  (( sleep_for > remaining )) && sleep_for="$remaining"
  sleep "$sleep_for"
done

show_progress 95 100 "Long stability and repeatability soak" "minimum unattended interval completed"

show_progress 95 0 "Final verification and packaging" "capturing final filter and capability state"
run_filter_capture "$OUT_DIR/filter-context-end.log"
run_inventory_counts "end" "$OUT_DIR/inventory/end.txt"
run_structural_read

END_EPOCH="$(date +%s)"
FINISHED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"
ELAPSED=$((END_EPOCH - START_EPOCH))

cat >"$OUT_DIR/SUMMARY.txt" <<EOF
Logic Co-Producer unattended validation session
Started: $STARTED_AT
Finished: $FINISHED_AT
Elapsed: $(fmt_time "$ELAPSED") ($ELAPSED seconds)
Minimum requested runtime: $(fmt_time "$MIN_SESSION_SECONDS")

Structural Event List reads: $STRUCTURAL_READS
Structural read failures: $STRUCTURAL_FAILURES
Paired exact A1 checkpoints: $EXACT_CHECKS
Exact checkpoint failures: $EXACT_FAILURES
Sanitized broader capability inventories: $INVENTORY_CHECKS
Recorded warnings: $WARNINGS
Recorded failures: $FAILURES

This session intentionally did not mutate MIDI, mixer, plug-in, routing, automation, or other project data.
Raw full-application AX snapshots were intentionally omitted to avoid collecting unrelated recent-file/menu history.
EOF

cat >"$OUT_DIR/TIMING.txt" <<EOF
Started:  $STARTED_AT
Finished: $FINISHED_AT
Elapsed seconds: $ELAPSED
Elapsed: $(fmt_time "$ELAPSED")
Minimum target seconds: $MIN_SESSION_SECONDS
EOF

show_progress 98 60 "Final verification and packaging" "creating one evidence ZIP"
(
  cd "$(dirname "$OUT_DIR")"
  /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
)
ZIP_STATUS=$?
if [[ "$ZIP_STATUS" -ne 0 ]]; then
  echo "Could not create evidence ZIP." >&2
  exit 6
fi

show_progress 100 100 "Final verification and packaging" "complete"

osascript -e 'display notification "Unattended validation session is complete." with title "Logic Co-Producer"' >/dev/null 2>&1 || true

printf "\n============================================================\n"
echo "VALIDATION SESSION COMPLETE"
printf "Total runtime: %s (%d seconds)\n" "$(fmt_time "$ELAPSED")" "$ELAPSED"
echo "Structural reads: $STRUCTURAL_READS ($STRUCTURAL_FAILURES failures)"
echo "Exact checkpoints: $EXACT_CHECKS ($EXACT_FAILURES failures)"
echo "Recorded failures: $FAILURES"
echo "Evidence ZIP: $ZIP_PATH"
echo "============================================================"

# The evidence package is useful even when individual probes failed; analysis
# should happen before asking the user to repeat anything.
exit 0
