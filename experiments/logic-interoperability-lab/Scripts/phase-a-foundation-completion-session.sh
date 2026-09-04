#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/foundation-completion-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-foundation-completion.zip"
RESULTS="${OUT}/results.txt"
OLD_ZIP="${TEST_ROOT}/coproducer-phase-a-completion.zip"
START_TS="$(date +%s)"
A6="NOT_RUN"; A7_NORMAL="NOT_RUN"; A7_SIDECHAIN="NOT_RUN"; A7="NOT_RUN"; A8="NOT_RUN"; A9="NOT_RUN"; A10="NOT_RUN"; A11="NOT_RUN"

mkdir -p "$OUT"
: > "$RESULTS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2

record(){ printf '%s\n' "$1" | tee -a "$RESULTS"; }
package(){ rm -f "$ZIP";(cd "$TEST_ROOT"&&/usr/bin/zip -qr "$ZIP" "$(basename "$OUT")")>/dev/null 2>&1||true; }
trap package EXIT

elapsed(){
  local now delta m s
  now="$(date +%s)"; delta=$((now-START_TS)); m=$((delta/60)); s=$((delta%60))
  printf '%dm%02ds' "$m" "$s"
}
heartbeat(){ record "PROGRESS elapsed=$(elapsed) $1"; }

summary_get(){
  python3 - "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]));v=d.get(sys.argv[2],'')
except Exception:v=''
print(v)
PY
}
write_summary(){
  python3 - "$OUT/summary.json" "$A6" "$A7_NORMAL" "$A7_SIDECHAIN" "$A7" "$A8" "$A9" "$A10" "$A11" <<'PY'
import json,sys
p,a6,a7n,a7s,a7,a8,a9,a10,a11=sys.argv[1:]
obj={'schema':'logic-coproducer-foundation-completion/1.2','A6':a6,'A7NormalRouting':a7n,'A7Sidechain':a7s,'A7':a7,'A8':a8,'A9':a9,'A10':a10,'A11':a11}
obj['allRequiredGatesPass']=all(obj[k]=='PASS' for k in ('A6','A7','A8','A9','A10','A11'))
json.dump(obj,open(p,'w'),indent=2,sort_keys=True)
PY
}
safety_stop(){
  local gate="$1" reason="$2"
  write_summary
  record "RESULT=FOUNDATION_SAFETY_FAIL gate=${gate} reason=${reason}"
  package
  exit 30
}

# Run a component with live output plus a heartbeat every 20 seconds even when
# Logic itself emits nothing. The component's real exit code is written to a
# sidecar rather than relying on pipeline semantics that differ across shells.
run_live(){
  local label="$1" logfile="$2"; shift 2
  local rcfile="${logfile}.rc" pid rc
  rm -f "$rcfile"
  (
    "$@"
    printf '%s\n' "$?" > "$rcfile"
  ) 2>&1 | tee "$logfile" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 20
    if kill -0 "$pid" 2>/dev/null; then heartbeat "active=${label}"; fi
  done
  wait "$pid" 2>/dev/null || true
  rc="$(cat "$rcfile" 2>/dev/null || echo 99)"
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=99
  return "$rc"
}

record "Logic Co-Producer — revised foundational Logic qualification A6-A11"
record "Safety policy: ordinary independent failures continue; restoration uncertainty stops the session."
record "Live progress is streamed below; a heartbeat is printed at least every 20 seconds during long component operations."
heartbeat "overall=0% preparing A6-A11 session"

# ---------------------------------------------------------------------------
# A6-A9. The original component has one Bash-3.2-only local-initialization bug
# in its progress-bar helper. Patch only that helper into a disposable local
# copy before execution; the test logic itself remains byte-for-byte unchanged.
# ---------------------------------------------------------------------------
record "STEP=1 component=A6-A9 begin"
heartbeat "overall~5% A6-A9 automation/routing/saved-state/audio-source qualification"
rm -f "$OLD_ZIP"
PHASE_A_COMPAT="$OUT/phase-a-completion-session.compat.sh"
python3 - "$ROOT/Scripts/phase-a-completion-session.sh" "$PHASE_A_COMPAT" <<'PY'
import sys
src,dst=sys.argv[1:]
s=open(src).read()
old='bar() { local d="$1" t="$2" w=20 f=$((d*w/t));'
new='bar() { local d="$1" t="$2" w=20 f; f=$((d*w/t));'
if old not in s:
    print('compat patch target not found',file=sys.stderr); raise SystemExit(2)
s=s.replace(old,new,1)
open(dst,'w').write(s)
PY
patch_rc=$?
if (( patch_rc != 0 )); then
  write_summary; record "RESULT=FOUNDATION_FAIL reason=A6-A9-bash3-compat-patch-failed"; exit 20
fi
chmod 700 "$PHASE_A_COMPAT" 2>/dev/null || true
run_live "A6-A9" "$OUT/a6-a9-terminal.log" bash "$PHASE_A_COMPAT"
rc=$?
if (( rc == 30 )); then safety_stop A6-A9 component-reported-unproven-restoration; fi
if (( rc != 0 )); then
  write_summary
  record "RESULT=FOUNDATION_FAIL reason=A6-A9-common-preflight-or-runner-failure rc=${rc}"
  exit 20
fi
if [[ -f "$OLD_ZIP" ]]; then
  cp "$OLD_ZIP" "$OUT/a6-a9-evidence.zip"
  mkdir -p "$OUT/a6-a9-evidence"
  /usr/bin/unzip -q "$OLD_ZIP" -d "$OUT/a6-a9-evidence" || true
fi
OLD_SUMMARY="$(find "$OUT/a6-a9-evidence" -name summary.json -type f 2>/dev/null | head -n 1)"
if [[ -n "$OLD_SUMMARY" && -f "$OLD_SUMMARY" ]]; then
  A6="$(summary_get "$OLD_SUMMARY" A6)"; A7_NORMAL="$(summary_get "$OLD_SUMMARY" A7)"; A8="$(summary_get "$OLD_SUMMARY" A8)"; A9="$(summary_get "$OLD_SUMMARY" A9)"
else
  A6="FAIL"; A7_NORMAL="FAIL"; A8="FAIL"; A9="FAIL"
  record "NOTICE=A6-A9 summary unavailable; component evidence retained"
fi
record "STEP=1_RESULT A6=${A6} A7_NORMAL=${A7_NORMAL} A8=${A8} A9=${A9}"
heartbeat "overall~45% A6-A9 component finished"

# ---------------------------------------------------------------------------
# A10 + distinct A7 sidechain case.
# ---------------------------------------------------------------------------
record "STEP=2 component=A10+A7-sidechain begin"
heartbeat "overall~50% testing stock effects and real Compressor sidechain"
mkdir -p "$OUT/a10"
run_live "A10+A7-sidechain" "$OUT/a10-terminal.log" bash "$ROOT/Scripts/a10-stock-plugin-validation-session-v2.sh" "$OUT/a10"
rc=$?
if (( rc == 30 )); then safety_stop A10 stock-plugin-chain-restoration-unproven; fi
if [[ -f "$OUT/a10/a10-summary.json" ]]; then
  A10="$(summary_get "$OUT/a10/a10-summary.json" A10)"
  A7_SIDECHAIN="$(summary_get "$OUT/a10/a10-summary.json" A7Sidechain)"
else
  A10="FAIL"; A7_SIDECHAIN="FAIL"
fi
[[ "$A7_NORMAL" == "PASS" && "$A7_SIDECHAIN" == "PASS" ]] && A7="PASS" || A7="FAIL"
record "STEP=2_RESULT A10=${A10} A7_SIDECHAIN=${A7_SIDECHAIN} A7_COMBINED=${A7}"
heartbeat "overall~85% stock-effect/sidechain component finished"

# ---------------------------------------------------------------------------
# A11: disposable MusicXML track + region + stock-instrument construction.
# ---------------------------------------------------------------------------
record "STEP=3 component=A11 begin"
heartbeat "overall~88% testing disposable track, MIDI region and stock instrument construction"
mkdir -p "$OUT/a11"
run_live "A11" "$OUT/a11-terminal.log" bash "$ROOT/Scripts/a11-construction-validation-session-v2.sh" "$OUT/a11"
rc=$?
if (( rc == 30 )); then safety_stop A11 disposable-construction-restoration-unproven; fi
if [[ -f "$OUT/a11/a11-summary.json" ]]; then A11="$(summary_get "$OUT/a11/a11-summary.json" A11)"; else A11="FAIL"; fi
record "STEP=3_RESULT A11=${A11}"

write_summary
record "FOUNDATION_GATE_SUMMARY A6=${A6} A7=${A7} A8=${A8} A9=${A9} A10=${A10} A11=${A11}"
heartbeat "overall=100% complete"
package
if [[ "$A6" == "PASS" && "$A7" == "PASS" && "$A8" == "PASS" && "$A9" == "PASS" && "$A10" == "PASS" && "$A11" == "PASS" ]]; then
  record "RESULT=FOUNDATION_PASS safety_restoration=verified"
else
  record "RESULT=FOUNDATION_SESSION_COMPLETE qualification=PARTIAL safety_restoration=verified"
fi
printf 'Evidence ZIP: %s\n' "$ZIP"
