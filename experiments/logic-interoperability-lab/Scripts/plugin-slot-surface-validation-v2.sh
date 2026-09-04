#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTROOT="$HOME/Desktop/logic-coproducer-tests/plugin-slot-surface-v2-$STAMP"
ZIP="$HOME/Desktop/logic-coproducer-tests/coproducer-plugin-slot-surface-v2.zip"
mkdir -p "$OUTROOT"

printf 'Logic Co-Producer — short plugin slot surface validation v2\n'
printf 'This probe does not insert or remove a plug-in.\n'
printf 'It opens one empty Audio FX slot menu, observes it, presses Escape, and verifies the chain stayed empty.\n\n'

cd "$ROOT"

set +e
swift build --product logic-plugin-slot-surface-probe-v2 >"$OUTROOT/build.log" 2>&1
BUILD_RC=$?
set -e
if [[ $BUILD_RC -ne 0 ]]; then
  cat "$OUTROOT/build.log"
  echo 'RESULT=FAIL reason=build-failed'
  exit 20
fi

.build/debug/logic-lab doctor >"$OUTROOT/doctor.log" 2>&1 || true

set +e
.build/debug/logic-plugin-slot-surface-probe-v2 \
  --track "Audio 1" \
  --out "$OUTROOT/plugin-slot-surface-v2.json" \
  >"$OUTROOT/probe.log" 2>&1
RC=$?
set -e

cat "$OUTROOT/probe.log"

rm -f "$ZIP"
(
  cd "$(dirname "$OUTROOT")"
  /usr/bin/zip -qry "$ZIP" "$(basename "$OUTROOT")"
)

printf '\nEvidence ZIP: %s\n' "$ZIP"

case "$RC" in
  0)
    echo 'RESULT=PASS'
    ;;
  10)
    echo 'RESULT=NEEDS_ANALYSIS'
    ;;
  30)
    echo 'RESULT=SAFETY_FAIL'
    ;;
  *)
    echo 'RESULT=NEEDS_ANALYSIS'
    ;;
esac

exit "$RC"
