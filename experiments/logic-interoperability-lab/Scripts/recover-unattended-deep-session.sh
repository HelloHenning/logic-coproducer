#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

TEST_ROOT="${LOGIC_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-unattended-deep-session}"
RECORDED_FAILED="$OUT_DIR/recovery-current.json"
BASELINE="$OUT_DIR/baseline-1.json"

[[ -f "$RECORDED_FAILED" ]] || { echo "Missing recorded failed-state snapshot: $RECORDED_FAILED" >&2; exit 2; }
[[ -f "$BASELINE" ]] || { echo "Missing protected baseline: $BASELINE" >&2; exit 2; }

echo "Logic Co-Producer — exact recovery after unattended velocity abort"
echo "This does not rerun the validation suite."
echo "It first reads the complete current region without changing it."
echo "It will write only if current Logic still exactly matches the recorded one-event failed state."
echo

if ! swift build >/dev/null; then
  echo "RESULT=RECOVERY_FAIL reason=build" >&2
  exit 2
fi

ACTOR="$LAB_DIR/.build/debug/logic-external-midi-actor"
LAB="$LAB_DIR/.build/debug/logic-lab"
BLIND="$LAB_DIR/.build/debug/logic-blind-diff"

BEFORE_JSON="$OUT_DIR/recovery-live-before.json"
BEFORE_LOG="$OUT_DIR/recovery-live-before.log"
PRECHECK_BASELINE_LOG="$OUT_DIR/recovery-precheck-baseline.log"
PRECHECK_FAILED_LOG="$OUT_DIR/recovery-precheck-recorded-failed.log"
RESTORE_PLAN="$OUT_DIR/velocity-emergency-restore-plan.json"
RESTORE_LOG="$OUT_DIR/velocity-emergency-restore.log"
FINAL_JSON="$OUT_DIR/recovered-final.json"
FINAL_LOG="$OUT_DIR/recovered-final.log"
EQUAL_LOG="$OUT_DIR/recovered-final-equal.log"

capture_full() {
  local out_json="$1"
  local out_log="$2"
  if ! "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$out_json" >"$out_log" 2>&1; then
    cat "$out_log" >&2
    return 1
  fi
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$out_log" || return 1
  grep -q 'rows_with_position=267 of 267' "$out_log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$out_log" || return 1
}

echo "1/3 Reading current Logic state..."
if ! capture_full "$BEFORE_JSON" "$BEFORE_LOG"; then
  echo "RESULT=RECOVERY_FAIL reason=current-read-incomplete" >&2
  exit 31
fi

if "$BLIND" assert-equal --pre "$BASELINE" --post "$BEFORE_JSON" >"$PRECHECK_BASELINE_LOG" 2>&1; then
  cat "$PRECHECK_BASELINE_LOG"
  echo "RESULT=RECOVERY_PASS full_region_matches_protected_baseline already_restored=true"
  exit 0
fi

if ! "$BLIND" assert-equal --pre "$RECORDED_FAILED" --post "$BEFORE_JSON" >"$PRECHECK_FAILED_LOG" 2>&1; then
  cat "$PRECHECK_BASELINE_LOG" >&2
  cat "$PRECHECK_FAILED_LOG" >&2
  echo "RESULT=RECOVERY_FAIL reason=current-state-is-neither-protected-baseline-nor-recorded-failed-state" >&2
  echo "No mutation was attempted." >&2
  exit 30
fi

echo "2/3 Current state exactly matches the recorded one-event failure; restoring that value..."
set +e
"$ACTOR" restore-field \
  --baseline-current "$BEFORE_JSON" \
  --restore-source "$BASELINE" \
  --row-index 9 \
  --field value \
  --label velocity-emergency-restore \
  --plan "$RESTORE_PLAN" >"$RESTORE_LOG" 2>&1
ACTOR_RC=$?
set -e

echo "3/3 Independently rereading all 267 events..."
if ! capture_full "$FINAL_JSON" "$FINAL_LOG"; then
  cat "$RESTORE_LOG" >&2
  echo "RESULT=RECOVERY_FAIL reason=final-read-incomplete actor_exit=$ACTOR_RC" >&2
  exit 31
fi

if "$BLIND" assert-equal --pre "$BASELINE" --post "$FINAL_JSON" >"$EQUAL_LOG" 2>&1; then
  cat "$RESTORE_LOG"
  cat "$EQUAL_LOG"
  if [[ $ACTOR_RC -ne 0 ]]; then
    echo "Note: the targeted actor returned $ACTOR_RC, but independent full-state verification proves recovery succeeded."
  fi
  echo "RESULT=RECOVERY_PASS full_region_matches_protected_baseline"
  exit 0
fi

cat "$RESTORE_LOG" >&2
cat "$EQUAL_LOG" >&2
echo "RESULT=RECOVERY_FAIL reason=full-state-diff actor_exit=$ACTOR_RC" >&2
exit 32
