#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$LAB_DIR"

EXPECTED="${1:-$HOME/Desktop/logic-a1-golden-v2.expected.json}"
OUT_DIR="${2:-$HOME/Desktop/logic-a2-test}"
ZIP_PATH="${OUT_DIR}.zip"
rm -rf "$OUT_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$OUT_DIR"

START=$SECONDS
MUTATED=0

fmt_time() { printf "%02dm %02ds" $(($1 / 60)) $(($1 % 60)); }

fail() {
  echo "A2 FAIL: $1" >&2
  exit "${2:-1}"
}

swift build >"$OUT_DIR/build.log" 2>&1 || fail "Swift build failed; see $OUT_DIR/build.log"
LAB=".build/debug/logic-lab"
MUT=".build/debug/logic-a2-mutate"
CMP=".build/debug/logic-a2-compare"
A1CMP=".build/debug/logic-a1-compare"

capture() {
  local name="$1"
  "$LAB" event-list --hydrate-scroll --scroll-steps 16 --max-rows 2 --out "$OUT_DIR/$name.json" >"$OUT_DIR/$name.log" 2>&1 || return 1
  grep -q 'hydrate_scroll=end .*status_mismatches=0 .*restore=ok' "$OUT_DIR/$name.log" || return 1
  grep -q 'rows_with_position=267 of 267' "$OUT_DIR/$name.log" || return 1
  grep -q 'rows_with_channel=267 of 267' "$OUT_DIR/$name.log" || return 1
}

emergency_restore() {
  if [[ "$MUTATED" -eq 1 ]]; then
    echo "Attempting automatic restoration after interrupted/failed A2 test..." >&2
    "$MUT" --from 62 --to 61 >"$OUT_DIR/emergency-restore.log" 2>&1 || true
  fi
}
trap emergency_restore EXIT INT TERM

echo "Logic Co-Producer A2 — controlled one-event MIDI mutation"
echo "Synthetic target only: channel 1, bar 1 beat 1, C#3 -> D3 -> C#3"
echo "The script captures the complete region before/after, verifies exact collateral diff, then restores it."
echo

echo "[1/7] Capturing authoritative pre-state..."
capture pre || fail "Could not capture a clean complete pre-state. Keep the corrected channel-1 fixture selected and Event List visible."

echo "[2/7] Applying one pitch change through Event List Accessibility..."
"$MUT" --from 61 --to 62 >"$OUT_DIR/mutation.log" 2>&1 || fail "The controlled AX write did not succeed. See $OUT_DIR/mutation.log"
grep -q 'RESULT=WRITE_OK' "$OUT_DIR/mutation.log" || fail "The write was not independently readable immediately after mutation."
MUTATED=1

echo "[3/7] Re-reading the complete mutated region..."
capture post || fail "Could not capture a clean complete post-mutation state."

echo "[4/7] Verifying exactly one semantic field changed..."
"$CMP" --pre "$OUT_DIR/pre.json" --post "$OUT_DIR/post.json" --mode mutation >"$OUT_DIR/mutation-compare.log" 2>&1 || fail "Mutation caused an unexpected canonical diff. See $OUT_DIR/mutation-compare.log"
grep -q 'RESULT=PASS' "$OUT_DIR/mutation-compare.log" || fail "Mutation comparator did not PASS."

echo "[5/7] Restoring the original C#3 pitch..."
"$MUT" --from 62 --to 61 >"$OUT_DIR/restore.log" 2>&1 || fail "Automatic restoration write failed. See $OUT_DIR/restore.log"
grep -q 'RESULT=WRITE_OK' "$OUT_DIR/restore.log" || fail "Restoration was not readable immediately after the write."
MUTATED=0

echo "[6/7] Re-reading and verifying exact restoration..."
capture restored || fail "Could not capture a clean restored state."
"$CMP" --pre "$OUT_DIR/pre.json" --post "$OUT_DIR/restored.json" --mode restore >"$OUT_DIR/restore-compare.log" 2>&1 || fail "Restored region is not identical to pre-state. See $OUT_DIR/restore-compare.log"

"$A1CMP" --expected "$EXPECTED" --run1 "$OUT_DIR/pre.json" --run2 "$OUT_DIR/restored.json" --out "$OUT_DIR/golden-report.json" >"$OUT_DIR/golden-compare.log" 2>&1 || fail "Golden verification failed. See $OUT_DIR/golden-compare.log"
grep -q 'RESULT=PASS' "$OUT_DIR/golden-compare.log" || fail "Golden verification did not PASS."

echo "[7/7] Packaging evidence..."
ELAPSED=$((SECONDS - START))
cat >"$OUT_DIR/SUMMARY.txt" <<EOF
POC A2 controlled one-event mutation
Elapsed: $(fmt_time "$ELAPSED")
Target: channel 1 note at 1 1 1 1, MIDI pitch 61 -> 62 -> 61
Pre-state complete capture: PASS
Mutation write/readback: PASS
Canonical mutation diff (one row; pitch field only): PASS
Restoration exact equality: PASS
Golden pre/restored verification: PASS
RESULT=PASS
EOF
(
  cd "$(dirname "$OUT_DIR")"
  /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
) || fail "Could not create evidence ZIP."

trap - EXIT INT TERM

echo
echo "A2 RESULT=PASS"
printf "Runtime: %s\n" "$(fmt_time "$ELAPSED")"
echo "Evidence ZIP: $ZIP_PATH"
