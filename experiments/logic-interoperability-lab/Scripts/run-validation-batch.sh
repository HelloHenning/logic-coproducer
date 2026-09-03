#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HOME/Desktop/coproducer-validation-batch}"
ZIP_PATH="${OUT_DIR}.zip"
START_EPOCH="$(date +%s)"
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"

set +e
bash "$SCRIPT_DIR/coproducer-validation-batch.sh" "$@"
STATUS=$?
set -e

END_EPOCH="$(date +%s)"
FINISHED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"
ELAPSED=$((END_EPOCH - START_EPOCH))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

mkdir -p "$OUT_DIR"
cat >"$OUT_DIR/TIMING.txt" <<EOF
Logic Co-Producer validation batch timing
Started:  $STARTED_AT
Finished: $FINISHED_AT
Elapsed seconds: $ELAPSED
Elapsed: ${ELAPSED_MIN}m ${ELAPSED_SEC}s
Exit status: $STATUS
EOF

if [[ -f "$OUT_DIR/SUMMARY.txt" ]]; then
  {
    echo
    echo "Timing: ${ELAPSED_MIN}m ${ELAPSED_SEC}s total (${ELAPSED} seconds)"
    echo "Started: $STARTED_AT"
    echo "Finished: $FINISHED_AT"
  } >>"$OUT_DIR/SUMMARY.txt"
fi

# Refresh the ZIP so final timing is included in the uploadable evidence bundle.
if [[ -d "$OUT_DIR" ]]; then
  (
    cd "$(dirname "$OUT_DIR")"
    /usr/bin/zip -qr "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
  )
fi

echo
printf "Total validation runtime: %dm %02ds (%d seconds)\n" "$ELAPSED_MIN" "$ELAPSED_SEC" "$ELAPSED"
echo "Timing record: $OUT_DIR/TIMING.txt"
echo "Evidence ZIP:  $ZIP_PATH"

exit "$STATUS"
