#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/plugin-slot-surface-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-plugin-slot-surface.zip"
PROBE="${ROOT}/.build/debug/logic-plugin-slot-surface-probe"

mkdir -p "$OUT"
rm -f "$ZIP"
trap 'cd "$TEST_ROOT" 2>/dev/null && /usr/bin/zip -qr "$ZIP" "$(basename "$OUT")" >/dev/null 2>&1 || true' EXIT

printf '%s\n' "Logic Co-Producer — short plug-in slot surface validation"
printf '%s\n' "Purpose: confirm Logic 12.0.1 exposes the researched empty Audio FX slot action/menu without inserting anything."
printf '%s\n' "Expected runtime: about 1–3 minutes."
printf '%s\n' "Leave Logic untouched until this command finishes."
printf '%s\n' "Evidence: $ZIP"
printf '\n'

cd "$ROOT" || exit 2
printf '%s\n' "STEP=1 build_and_preflight"
swift build > "$OUT/build.log" 2>&1 || { printf '%s\n' "RESULT=FAIL reason=build"; exit 20; }
"$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || true
if ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log" || ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then
  cat "$OUT/doctor.log"
  printf '%s\n' "RESULT=FAIL reason=logic-or-accessibility-preflight"
  exit 20
fi

printf '%s\n' "STEP=2 inspect_exact_Audio_1_insert_surface"
"$PROBE" --track "Audio 1" --out "$OUT/plugin-slot-surface.json" 2>&1 | tee "$OUT/probe.log"
RC=${PIPESTATUS[0]}

if (( RC == 30 )); then
  printf '%s\n' "RESULT=SAFETY_FAIL reason=plugin-chain-not-proven-unchanged"
  exit 30
fi
if (( RC == 0 )); then
  printf '%s\n' "RESULT=PASS next=verified-compressor-insert-probe"
  exit 0
fi
if (( RC == 10 )); then
  printf '%s\n' "RESULT=NEEDS_ANALYSIS reason=logic-12.0.1-surface-differs-from-prior-art"
  exit 10
fi
printf '%s\n' "RESULT=FAIL reason=probe-error rc=$RC"
exit "$RC"
