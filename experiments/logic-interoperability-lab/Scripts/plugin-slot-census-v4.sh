#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTROOT="$HOME/Desktop/logic-coproducer-tests/plugin-slot-census-v4-$STAMP"
ZIP="$HOME/Desktop/logic-coproducer-tests/coproducer-plugin-slot-census-v4.zip"
mkdir -p "$OUTROOT"

printf 'Logic Co-Producer — read-only plugin slot census v4\n'
printf 'This probe does not open a plug-in menu and does not change the project.\n'
printf 'Unlike v3, it first resolves a named Mixer container and only then inspects the Audio 1 mixer channel strip.\n\n'

cd "$ROOT"

set +e
swift build --product logic-plugin-slot-census-v4 >"$OUTROOT/build.log" 2>&1
BUILD_RC=$?
set -e
if [[ $BUILD_RC -ne 0 ]]; then
  cat "$OUTROOT/build.log"
  echo 'RESULT=FAIL reason=build-failed'
  exit 20
fi

.build/debug/logic-lab doctor >"$OUTROOT/doctor.log" 2>&1 || true

set +e
.build/debug/logic-plugin-slot-census-v4 \
  --track "Audio 1" \
  --out "$OUTROOT/plugin-slot-census-v4.json" \
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
  0) echo 'RESULT=PASS census_captured=yes' ;;
  10) echo 'RESULT=NEEDS_MIXER_VISIBLE' ;;
  30) echo 'RESULT=SAFETY_FAIL' ;;
  *) echo 'RESULT=NEEDS_ANALYSIS' ;;
esac

exit "$RC"
