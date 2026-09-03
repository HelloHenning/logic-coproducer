#!/bin/bash
set -euo pipefail

EXPECTED="${1:-$HOME/Desktop/logic-a1-golden-v2.expected.json}"
OUT_DIR="${2:-$HOME/Desktop/logic-a1-test}"
SCROLL_STEPS="${A1_SCROLL_STEPS:-16}"

if [[ ! -f "$EXPECTED" ]]; then
  echo "A1 test: expected manifest not found: $EXPECTED" >&2
  echo "Pass it as the first argument, or generate the corrected golden fixture first." >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
RUN1_JSON="$OUT_DIR/observed-run1.json"
RUN2_JSON="$OUT_DIR/observed-run2.json"
RUN1_LOG="$OUT_DIR/observed-run1.log"
RUN2_LOG="$OUT_DIR/observed-run2.log"
REPORT_JSON="$OUT_DIR/report.json"

capture_run() {
  local run_number="$1"
  local json_path="$2"
  local log_path="$3"

  echo "Capturing run $run_number..."
  if ! swift run logic-lab event-list \
    --hydrate-scroll \
    --scroll-steps "$SCROLL_STEPS" \
    --max-rows 1 \
    --out "$json_path" >"$log_path" 2>&1; then
    echo "A1 test: capture run $run_number failed." >&2
    tail -n 30 "$log_path" >&2
    exit 7
  fi

  if ! grep -Eq 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$log_path"; then
    echo "A1 test: run $run_number did not verify a clean hydration sweep and scroll restore." >&2
    tail -n 30 "$log_path" >&2
    exit 7
  fi

  if grep -q 'hydrate_warning=' "$log_path"; then
    echo "A1 test: run $run_number emitted a hydration warning." >&2
    tail -n 30 "$log_path" >&2
    exit 7
  fi

  local position_line channel_line
  position_line="$(grep '^rows_with_position=' "$log_path" | tail -n 1 || true)"
  channel_line="$(grep '^rows_with_channel=' "$log_path" | tail -n 1 || true)"
  echo "Run $run_number capture OK: ${position_line:-position coverage unavailable}; ${channel_line:-channel coverage unavailable}; scroll restore OK"
}

echo "A1 automated Event List test"
echo "Expected manifest: $EXPECTED"
echo "Evidence folder:   $OUT_DIR"
echo

capture_run 1 "$RUN1_JSON" "$RUN1_LOG"
capture_run 2 "$RUN2_JSON" "$RUN2_LOG"

echo
echo "Exact golden + repeatability comparison:"
swift run logic-a1-compare \
  --expected "$EXPECTED" \
  --run1 "$RUN1_JSON" \
  --run2 "$RUN2_JSON" \
  --out "$REPORT_JSON"

echo
echo "Evidence saved in: $OUT_DIR"
