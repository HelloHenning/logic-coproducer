#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-${TEST_ROOT}/a10-stock-plugin-${STAMP}}"
COMMANDS="${OUT}/bridge-commands.txt"
STATUS="${OUT}/bridge-status.json"
EVENTS="${OUT}/bridge-events.jsonl"
BRIDGE_LOG="${OUT}/bridge.log"
RESULTS="${OUT}/results.txt"
TARGET_TRACK="Audio 1"
SIDECHAIN_SOURCE="Studio Grand"
BRIDGE_PID=""
A10="PASS"
SIDECHAIN="FAIL"

mkdir -p "$OUT"
: > "$RESULTS"
: > "$COMMANDS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2

record() { printf '%s\n' "$1" | tee -a "$RESULTS"; }

cleanup() {
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    printf 'PRESS TRACK\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.12
    printf 'QUIT\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.2
    kill "$BRIDGE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

json_get() {
  python3 - "$1" "$2" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1])); v=d
except Exception: print(''); raise SystemExit
for p in sys.argv[2].split('.'):
    v=v.get(p) if isinstance(v,dict) else None
if v is None: print('')
elif isinstance(v,bool): print('true' if v else 'false')
else: print(v)
PY
}
bridge_alive() { [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; }
wait_counter_gt() {
  local key="$1" before="$2" timeout="${3:-4}" start value
  start=$(date +%s)
  while true; do
    bridge_alive || return 2
    value="$(json_get "$STATUS" "$key")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value > before )); then return 0; fi
    (( $(date +%s) - start >= timeout )) && return 1
    sleep 0.08
  done
}
send_command() {
  local command="$1" timeout="${2:-3}" before
  before="$(json_get "$STATUS" commandAck)"; [[ "$before" =~ ^[0-9]+$ ]] || before=0
  printf '%s\n' "$command" >> "$COMMANDS"
  wait_counter_gt commandAck "$before" "$timeout"
}
send_display() {
  local command="$1" timeout="${2:-4}" before
  before="$(json_get "$STATUS" lcdRevision)"; [[ "$before" =~ ^[0-9]+$ ]] || before=0
  send_command "$command" "$timeout" || return 1
  wait_counter_gt lcdRevision "$before" 1 >/dev/null 2>&1 || true
  sleep 0.12
}

segment() {
  local row="$1" slot="$2"
  python3 - "$STATUS" "$row" "$slot" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
raw=str(d.get(sys.argv[2],'' )).ljust(56)[:56]; i=int(sys.argv[3])
if i<0 or i>7:sys.exit(2)
print(raw[i*7:(i+1)*7].strip())
PY
}
find_track_column() {
  python3 - "$STATUS" "$TARGET_TRACK" <<'PY'
import json,sys,re
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
q=' '.join(sys.argv[2].lower().split())
u=str(d.get('lcdUpper','')).ljust(56)[:56]
segs=[u[i:i+7].strip() for i in range(0,56,7)]
h=[]
for i,s in enumerate(segs):
    n=' '.join(s.lower().split())
    score=0
    if n==q:score=20
    elif q in n or n in q:score=10
    elif q.replace(' ','')==n.replace(' ',''):score=15
    if score:h.append((score,i,s))
if not h:sys.exit(2)
h.sort(reverse=True)
if len(h)>1 and h[0][0]==h[1][0]:sys.exit(3)
print(h[0][1])
PY
}
show_lcd() {
  local label="$1"
  python3 - "$STATUS" "$label" <<'PY' | tee -a "$RESULTS"
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(0)
for k in ('lcdUpper','lcdLower'):
 r=str(d.get(k,'')).ljust(56)[:56]; print(sys.argv[2],k,repr([r[i:i+7].strip() for i in range(0,56,7)]))
PY
}

ensure_plugin_mixer() {
  "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TARGET_TRACK" >/dev/null 2>&1 || return 1
  for _ in 1 2 3; do
    send_display "PRESS PLUGIN" 4 || return 1
    if find_track_column >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

home_insert_one() {
  local col="$1"
  for _ in $(seq 1 18); do send_display "PRESS UP" 2 || return 1; done
  return 0
}

find_empty_insert() {
  local col="$1" slot lower
  home_insert_one "$col" || return 1
  for slot in $(seq 1 15); do
    lower="$(segment lcdLower "$col" 2>/dev/null || true)"
    record "A10_SCAN insert_slot=${slot} current=$(printf '%q' "$lower")"
    if [[ "${lower// /}" == "--" || -z "$lower" ]]; then printf '%s\n' "$slot"; return 0; fi
    (( slot < 15 )) && send_display "PRESS DOWN" 2 || true
  done
  return 1
}

matches_plugin() {
  local kind="$1" value="$2"
  python3 - "$kind" "$value" <<'PY'
import re,sys
kind=sys.argv[1]; s=' '.join(sys.argv[2].lower().replace('*','').split())
patterns={
 'channel_eq':[r'chan.*eq',r'ch\s*eq',r'chaneq'],
 'compressor':[r'compr',r'compress'],
 'distortion':[r'distor',r'^dist'],
 'chromaverb':[r'chroma',r'chromav'],
 'stereo_delay':[r'st.*d[el][ly]',r'ster.*d[el][ly]',r'stdelay',r'stdly']
}
raise SystemExit(0 if any(re.search(p,s) for p in patterns[kind]) else 1)
PY
}

preselect_plugin() {
  local col="$1" kind="$2" max="${3:-500}" i value
  for i in $(seq 1 "$max"); do
    send_display "VPOT ${col} 1" 2 || return 1
    value="$(segment lcdLower "$col" 2>/dev/null || true)"
    if matches_plugin "$kind" "$value"; then
      record "A10_PRESELECT kind=${kind} steps=${i} lcd=$(printf '%q' "$value")"
      return 0
    fi
  done
  record "A10_PRESELECT_FAIL kind=${kind} reason=not-found-without-confirmation"
  return 1
}

cancel_preselection_to_empty() {
  local col="$1" value
  for _ in $(seq 1 520); do
    value="$(segment lcdLower "$col" 2>/dev/null || true)"
    [[ "${value// /}" == "--" || -z "$value" ]] && return 0
    send_display "VPOT ${col} -1" 2 || return 1
  done
  return 1
}

numeric_value_at() {
  local slot="$1"
  python3 - "$STATUS" "$slot" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
i=int(sys.argv[2]); r=str(d.get('lcdLower','')).ljust(56)[:56]; s=r[i*7:(i+1)*7].strip().replace(',','.')
m=re.search(r'[-+]?\d+(?:\.\d+)?',s)
if not m:sys.exit(2)
print(m.group(0)+'\t'+s)
PY
}

plugin_parameter_roundtrip() {
  local kind="$1" names=() name_row slot value_info baseline changed current step final_name
  # Normalize to Name mode: if several lower-row segments are numeric, toggle once.
  local numeric_count
  numeric_count="$(python3 - "$STATUS" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:print(0);raise SystemExit
r=str(d.get('lcdLower','')).ljust(56)[:56]
ss=[r[i:i+7].strip() for i in range(0,56,7)]
print(sum(bool(re.search(r'[-+]?\d+(?:[.,]\d+)?',s)) for s in ss if s))
PY
)"
  [[ "$numeric_count" =~ ^[0-9]+$ ]] || numeric_count=0
  if (( numeric_count >= 3 )); then send_display "PRESS NAMEVALUE" 3 || return 1; fi

  mapfile -t names < <(python3 - "$STATUS" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:raise SystemExit
r=str(d.get('lcdLower','')).ljust(56)[:56]
for i in range(8):
 s=r[i*7:(i+1)*7].strip()
 if s and re.search('[A-Za-z]',s) and not any(x in s.lower() for x in ('bypass','meter')): print(str(i)+'\t'+s)
PY
)
  ((${#names[@]})) || { record "A10_PARAM_FAIL kind=${kind} reason=no-semantic-parameter-names"; return 1; }
  send_display "PRESS NAMEVALUE" 3 || return 1

  slot=""; baseline=""; name_row=""
  local item idx candidate
  for item in "${names[@]}"; do
    idx="${item%%$'\t'*}"; candidate="${item#*$'\t'}"
    if value_info="$(numeric_value_at "$idx" 2>/dev/null)"; then
      slot="$idx"; baseline="${value_info%%$'\t'*}"; name_row="$candidate"; break
    fi
  done
  [[ -n "$slot" && -n "$baseline" ]] || { record "A10_PARAM_FAIL kind=${kind} reason=no-semantic-numeric-parameter"; return 1; }
  record "A10_PARAM kind=${kind} name=$(printf '%q' "$name_row") slot=${slot} baseline=${baseline}"

  send_display "VPOT ${slot} 1" 3 || return 1
  sleep 0.15
  changed="$(numeric_value_at "$slot" 2>/dev/null | cut -f1 || true)"
  if [[ -z "$changed" ]] || python3 - "$changed" "$baseline" <<'PY' >/dev/null 2>&1
import math,sys
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  then
    send_display "VPOT ${slot} -1" 3 || return 1
    sleep 0.15
    changed="$(numeric_value_at "$slot" 2>/dev/null | cut -f1 || true)"
  fi
  [[ -n "$changed" ]] || { record "A10_PARAM_FAIL kind=${kind} reason=changed-value-unreadable"; return 1; }
  if python3 - "$changed" "$baseline" <<'PY' >/dev/null 2>&1
import math,sys
raise SystemExit(0 if not math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  then :; else record "A10_PARAM_FAIL kind=${kind} reason=no-change-observed"; return 1; fi
  record "A10_PARAM_CHANGED kind=${kind} before=${baseline} changed=${changed}"

  for _ in $(seq 1 20); do
    current="$(numeric_value_at "$slot" 2>/dev/null | cut -f1 || true)"
    [[ -n "$current" ]] || break
    if python3 - "$current" "$baseline" <<'PY' >/dev/null 2>&1
import math,sys
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
    then break; fi
    step="$(python3 - "$current" "$baseline" <<'PY'
import sys
try:c=float(sys.argv[1]);b=float(sys.argv[2])
except Exception:print('');raise SystemExit
print(-1 if c>b else 1)
PY
)"
    [[ "$step" == "1" || "$step" == "-1" ]] || break
    send_display "VPOT ${slot} ${step}" 3 || break
  done
  current="$(numeric_value_at "$slot" 2>/dev/null | cut -f1 || true)"
  if [[ -z "$current" ]] || ! python3 - "$current" "$baseline" <<'PY' >/dev/null 2>&1
import math,sys
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  then record "A10_PARAM_FAIL kind=${kind} reason=temporary-parameter-baseline-not-restored current=${current:-unknown}"; return 1; fi

  # Independent semantic rerender: Name then Value, same slot/name and baseline.
  send_display "PRESS NAMEVALUE" 3 || return 1
  final_name="$(segment lcdLower "$slot" 2>/dev/null || true)"
  [[ -n "$final_name" ]] || { record "A10_PARAM_FAIL kind=${kind} reason=semantic-name-rerender-unreadable"; return 1; }
  send_display "PRESS NAMEVALUE" 3 || return 1
  current="$(numeric_value_at "$slot" 2>/dev/null | cut -f1 || true)"
  if [[ "$(printf '%s' "$final_name" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$name_row" | tr '[:upper:]' '[:lower:]')" ]]; then
    record "A10_PARAM_FAIL kind=${kind} reason=semantic-parameter-identity-changed before=$(printf '%q' "$name_row") final=$(printf '%q' "$final_name")"; return 1
  fi
  python3 - "$current" "$baseline" <<'PY' >/dev/null 2>&1 || { record "A10_PARAM_FAIL kind=${kind} reason=fresh-baseline-mismatch"; return 1; }
import math,sys
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  record "A10_PARAM_PASS kind=${kind} name=$(printf '%q' "$name_row") before=${baseline} changed=${changed} restored=${current}"
  return 0
}

compare_fingerprint() {
  local before="$1" after="$2"
  python3 - "$before" "$after" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]))
except Exception:sys.exit(2)
raise SystemExit(0 if a.get('occupiedSlots')==b.get('occupiedSlots') else 3)
PY
}

remove_current_plugin() {
  local col="$1" value
  ensure_plugin_mixer || return 1
  col="$(find_track_column 2>/dev/null)" || return 1
  for _ in $(seq 1 520); do
    value="$(segment lcdLower "$col" 2>/dev/null || true)"
    if [[ "${value// /}" == "--" || -z "$value" ]]; then
      send_display "VPOTPRESS ${col}" 3 || return 1
      sleep 0.25
      return 0
    fi
    send_display "VPOT ${col} -1" 2 || return 1
  done
  return 1
}

run_effect() {
  local index="$1" kind="$2" full="$3" baseline_fp="$4" col slot inserted=0 param_ok=0 final_fp
  record "A10_EFFECT_BEGIN index=${index} kind=${kind} plugin=$(printf '%q' "$full")"
  if ! ensure_plugin_mixer; then record "A10_EFFECT_FAIL kind=${kind} reason=plugin-mixer-not-resolved before_mutation=true"; A10="FAIL"; return; fi
  col="$(find_track_column 2>/dev/null)" || { record "A10_EFFECT_FAIL kind=${kind} reason=target-column-not-resolved before_mutation=true"; A10="FAIL"; return; }
  slot="$(find_empty_insert "$col" 2>/dev/null)" || { record "A10_EFFECT_FAIL kind=${kind} reason=no-empty-insert-slot before_mutation=true"; A10="FAIL"; return; }
  record "A10_EFFECT_TARGET kind=${kind} insert_slot=${slot} mcu_column=${col}"
  if ! preselect_plugin "$col" "$kind" 520; then
    cancel_preselection_to_empty "$col" >/dev/null 2>&1 || true
    record "A10_EFFECT_FAIL kind=${kind} reason=stock-plugin-not-found-before-confirmation protected_chain=unchanged"
    A10="FAIL"; return
  fi
  if ! send_display "VPOTPRESS ${col}" 4; then record "A10_SAFETY_FAIL kind=${kind} reason=confirm-command-path-lost state=ambiguous"; exit 30; fi
  inserted=1
  sleep 0.5
  if ! "$ROOT/.build/debug/logic-foundation-probe" plugin-window --name "$full" --out "$OUT/a10-${index}-${kind}-window.json" > "$OUT/a10-${index}-${kind}-window.log" 2>&1; then
    cat "$OUT/a10-${index}-${kind}-window.log" | tee -a "$RESULTS"
    record "A10_EFFECT_FAIL kind=${kind} reason=inserted-instance-identity-not-verified cleanup=required"
    A10="FAIL"
  else
    cat "$OUT/a10-${index}-${kind}-window.log" | tee -a "$RESULTS"
    if plugin_parameter_roundtrip "$kind"; then param_ok=1; else A10="FAIL"; fi
    if [[ "$kind" == "compressor" ]]; then
      if "$ROOT/.build/debug/logic-foundation-probe" sidechain-roundtrip --plugin "$full" --source "$SIDECHAIN_SOURCE" --out "$OUT/a7-sidechain.json" > "$OUT/a7-sidechain.log" 2>&1; then
        SIDECHAIN="PASS"; record "A7_SIDECHAIN_RESULT=PASS plugin=Compressor source=Studio_Grand restoration=verified"
      else
        rc=$?; cat "$OUT/a7-sidechain.log" | tee -a "$RESULTS"
        if (( rc == 30 )); then record "A10_SAFETY_FAIL gate=A7_sidechain reason=sidechain-restoration-unproven"; exit 30; fi
        SIDECHAIN="FAIL"; record "A7_SIDECHAIN_RESULT=FAIL reason=sidechain-roundtrip-not-qualified restoration=verified_or_no_mutation"
      fi
    fi
  fi

  if (( inserted )); then
    if ! remove_current_plugin "$col"; then record "A10_SAFETY_FAIL kind=${kind} reason=temporary-plugin-removal-unproven"; exit 30; fi
    final_fp="$OUT/a10-${index}-${kind}-final-fingerprint.json"
    if ! "$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$final_fp" > "$OUT/a10-${index}-${kind}-final-fingerprint.log" 2>&1; then
      record "A10_SAFETY_FAIL kind=${kind} reason=final-plugin-fingerprint-unavailable"; exit 30
    fi
    if ! compare_fingerprint "$baseline_fp" "$final_fp"; then
      record "A10_SAFETY_FAIL kind=${kind} reason=plugin-chain-fingerprint-mismatch-after-removal"; exit 30
    fi
    record "A10_EFFECT_CLEANUP=PASS kind=${kind} original_plugin_chain_restored=true"
  fi
  if (( param_ok )); then record "A10_EFFECT_RESULT=PASS kind=${kind} plugin=$(printf '%q' "$full")"; else record "A10_EFFECT_RESULT=FAIL kind=${kind}"; fi
}

record "Logic Co-Producer — A10 stock effects + A7 sidechain qualification"
if ! swift build > "$OUT/build.log" 2>&1; then record "RESULT=A10_FAIL reason=build"; exit 20; fi
if ! "$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log" || ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then
  record "RESULT=A10_FAIL reason=doctor-or-accessibility"; exit 20
fi
if ! "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TARGET_TRACK" > "$OUT/target-track.log" 2>&1; then record "RESULT=A10_FAIL reason=Audio-1-not-resolved"; exit 20; fi
if ! "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$SIDECHAIN_SOURCE" > "$OUT/sidechain-source-track.log" 2>&1; then record "RESULT=A10_FAIL reason=Studio-Grand-not-resolved"; exit 20; fi
BASE_FP="$OUT/a10-baseline-fingerprint.json"
if ! "$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$BASE_FP" > "$OUT/a10-baseline-fingerprint.log" 2>&1; then record "RESULT=A10_FAIL reason=baseline-plugin-fingerprint"; exit 20; fi

"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS" > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
for _ in $(seq 1 70); do bridge_alive || break; [[ "$(json_get "$STATUS" ready)" == "true" ]] && break; sleep 0.1; done
if [[ "$(json_get "$STATUS" ready)" != "true" ]] || ! bridge_alive; then record "RESULT=A10_FAIL reason=mcu-bridge-not-ready"; exit 20; fi
connected=0
for _ in $(seq 1 120); do packets="$(json_get "$STATUS" hostPacketCount)"; [[ "$packets" =~ ^[0-9]+$ ]] || packets=0; if ((packets>0));then connected=1;break;fi; bridge_alive||break;sleep 0.1;done
if (( ! connected )); then record "RESULT=A10_FAIL reason=existing-mcu-binding-not-detected"; exit 20; fi

run_effect 1 channel_eq "Channel EQ" "$BASE_FP"
run_effect 2 compressor "Compressor" "$BASE_FP"
run_effect 3 distortion "Distortion" "$BASE_FP"
run_effect 4 chromaverb "ChromaVerb" "$BASE_FP"
run_effect 5 stereo_delay "Stereo Delay" "$BASE_FP"

FINAL_FP="$OUT/a10-final-fingerprint.json"
"$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$FINAL_FP" > "$OUT/a10-final-fingerprint.log" 2>&1 || { record "RESULT=A10_SAFETY_FAIL reason=final-fingerprint-unavailable"; exit 30; }
compare_fingerprint "$BASE_FP" "$FINAL_FP" || { record "RESULT=A10_SAFETY_FAIL reason=final-plugin-chain-mismatch"; exit 30; }
python3 - "$OUT/a10-summary.json" "$A10" "$SIDECHAIN" <<'PY'
import json,sys
json.dump({'schema':'logic-coproducer-a10-summary/1.0','A10':sys.argv[2],'A7Sidechain':sys.argv[3],'protectedPluginChainRestored':True},open(sys.argv[1],'w'),indent=2,sort_keys=True)
PY
record "A10_GATE_SUMMARY A10=${A10} A7_SIDECHAIN=${SIDECHAIN} protected_plugin_chain=restored"
if [[ "$A10" == "PASS" ]]; then record "RESULT=A10_PASS stock_effect_classes=5 chain_restoration=verified"; exit 0; fi
record "RESULT=A10_FAIL stock_effect_classes_not_all_qualified chain_restoration=verified"
exit 20
