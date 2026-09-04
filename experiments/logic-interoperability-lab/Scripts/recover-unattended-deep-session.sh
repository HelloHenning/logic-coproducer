#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

TEST_ROOT="${LOGIC_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-unattended-deep-session}"
CURRENT="$OUT_DIR/recovery-current.json"
BASELINE="$OUT_DIR/baseline-1.json"

[[ -f "$CURRENT" ]] || { echo "Missing recovery snapshot: $CURRENT" >&2; exit 2; }
[[ -f "$BASELINE" ]] || { echo "Missing protected baseline: $BASELINE" >&2; exit 2; }

echo "Logic Co-Producer — exact recovery after unattended velocity abort"
echo "This does not rerun the validation suite."
echo "It will restore only the one event/value recorded by the aborted session, then prove the full 267-event region equals the protected baseline."
echo

swift build >/dev/null
ACTOR="$LAB_DIR/.build/debug/logic-external-midi-actor"
LAB="$LAB_DIR/.build/debug/logic-lab"
BLIND="$LAB_DIR/.build/debug/logic-blind-diff"

RESTORE_PLAN="$OUT_DIR/velocity-emergency-restore-plan.json"
RESTORE_LOG="$OUT_DIR/velocity-emergency-restore.log"
FINAL_JSON="$OUT_DIR/recovered-final.json"
FINAL_LOG="$OUT_DIR/recovered-final.log"
EQUAL_LOG="$OUT_DIR/recovered-final-equal.log"

"$ACTOR" restore-field \
  --baseline-current "$CURRENT" \
  --restore-source "$BASELINE" \
  --row-index 9 \
  --field value \
  --label velocity-emergency-restore \
  --plan "$RESTORE_PLAN" >"$RESTORE_LOG" 2>&1

grep -q 'RESULT=RESTORE_OK' "$RESTORE_LOG" || {
  cat "$RESTORE_LOG" >&2
  echo "RESULT=RECOVERY_FAIL reason=targeted-restore-not-verified" >&2
  exit 30
}

"$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$FINAL_JSON" >"$FINAL_LOG" 2>&1

grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$FINAL_LOG" || {
  echo "RESULT=RECOVERY_FAIL reason=final-read-incomplete" >&2
  exit 31
}
grep -q 'rows_with_position=267 of 267' "$FINAL_LOG" || {
  echo "RESULT=RECOVERY_FAIL reason=position-coverage" >&2
  exit 31
}
grep -q 'rows_with_channel=267 of 267' "$FINAL_LOG" || {
  echo "RESULT=RECOVERY_FAIL reason=channel-coverage" >&2
  exit 31
}

"$BLIND" assert-equal --pre "$BASELINE" --post "$FINAL_JSON" >"$EQUAL_LOG" 2>&1 || {
  cat "$EQUAL_LOG" >&2
  echo "RESULT=RECOVERY_FAIL reason=full-state-diff" >&2
  exit 32
}

cat "$RESTORE_LOG"
cat "$EQUAL_LOG"
echo "RESULT=RECOVERY_PASS full_region_matches_protected_baseline"
