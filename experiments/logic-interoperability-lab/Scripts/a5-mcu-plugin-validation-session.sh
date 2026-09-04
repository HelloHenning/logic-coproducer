#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/a5-mcu-plugin-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-a5-plugin-session.zip"
COMMANDS="${OUT}/bridge-commands.txt"
STATUS="${OUT}/bridge-status.json"
EVENTS="${OUT}/bridge-events.jsonl"
BRIDGE_LOG="${OUT}/bridge.log"
RESULTS="${OUT}/results.txt"
EXPECTED_TRACK="Studio Grand"
BRIDGE_PID=""
INTERRUPTED=0
MUTATION_STARTED=0
RESTORATION_VERIFIED=0

mkdir -p "$OUT"
: > "$RESULTS"
: > "$COMMANDS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2

bar() {
  local done="$1" total="$2" width=20 filled empty
  filled=$(( done * width / total ))
  empty=$(( width - filled ))
  printf '['
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
  printf ']'
}

progress() {
  local step="$1" total="$2" current="$3" action="$4"
  printf '\nOverall  '; bar "$step" "$total"; printf ' %3d%%  Step %d of %d\n' "$(( step * 100 / total ))" "$step" "$total"
  printf 'Current  '; bar "$current" 100; printf ' %3d%%  %s\n' "$current" "$action"
}

record() { printf '%s\n' "$1" | tee -a "$RESULTS"; }

package_evidence() {
  [[ -d "$OUT" ]] || return 0
  rm -f "$ZIP"
  (cd "$TEST_ROOT" && /usr/bin/zip -qr "$ZIP" "$(basename "$OUT")") >/dev/null 2>&1 || true
}

bridge_alive() {
  [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null
}

cleanup() {
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    printf 'PRESS TRACK\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.15
    printf 'QUIT\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.2
    kill "$BRIDGE_PID" 2>/dev/null || true
  fi
  package_evidence
}

on_interrupt() {
  INTERRUPTED=1
  record "NOTICE=interrupt-requested will-stop-at-safe-checkpoint"
}

trap cleanup EXIT
trap on_interrupt INT TERM HUP

abort_if_interrupted() {
  if (( INTERRUPTED )); then
    if (( MUTATION_STARTED && ! RESTORATION_VERIFIED )); then
      record "RESULT=A5_SAFETY_FAIL reason=interrupted-with-restoration-unproven"
      exit 30
    fi
    record "RESULT=A5_FAIL reason=interrupted protected_state=$([[ $RESTORATION_VERIFIED -eq 1 ]] && echo restored || echo unchanged)"
    exit 130
  fi
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json,sys
p,key=sys.argv[1],sys.argv[2]
try:
    with open(p) as f: d=json.load(f)
    v=d
    for part in key.split('.'):
        v=v.get(part) if isinstance(v,dict) else None
    if v is None: print('')
    elif isinstance(v,bool): print('true' if v else 'false')
    elif isinstance(v,(dict,list)): print(json.dumps(v,separators=(',',':')))
    else: print(v)
except Exception:
    print('')
PY
}

wait_status_number_gt() {
  local key="$1" before="$2" timeout="${3:-4}" start now value
  start=$(date +%s)
  while true; do
    bridge_alive || return 2
    value="$(json_get "$STATUS" "$key")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value > before )); then return 0; fi
    now=$(date +%s)
    if (( now - start >= timeout )); then return 1; fi
    sleep 0.1
  done
}

send_command() {
  local command="$1" timeout="${2:-3}" before
  before="$(json_get "$STATUS" commandAck)"; [[ "$before" =~ ^[0-9]+$ ]] || before=0
  printf '%s\n' "$command" >> "$COMMANDS"
  wait_status_number_gt commandAck "$before" "$timeout"
}

send_display_command() {
  local command="$1" timeout="${2:-4}" before
  before="$(json_get "$STATUS" lcdRevision)"; [[ "$before" =~ ^[0-9]+$ ]] || before=0
  send_command "$command" "$timeout" || return 1
  wait_status_number_gt lcdRevision "$before" "$timeout" || true
  sleep 0.35
  return 0
}

capture_status() {
  local path="$1"
  cp "$STATUS" "$path" 2>/dev/null || true
}

capture_topology() {
  local path="$1"
  "$ROOT/.build/debug/logic-mixer-matrix" topology --out "$path" > "${path%.json}.log" 2>&1
}

track_identity_ok() {
  local path="$1"
  python3 - "$path" "$EXPECTED_TRACK" <<'PY'
import json,sys
p,label=sys.argv[1:]
try: d=json.load(open(p))
except Exception: sys.exit(2)
found=[]
for s in d.get('strips',[]):
    hints=[str(x).strip() for x in s.get('labelHints',[])]
    if label in hints or any(('“'+label+'”') in h for h in hints): found.append(s)
if len(found)!=1:
    print('FAIL track_identity_count='+str(len(found)))
    sys.exit(3)
print('PASS track_identity='+label+' strip='+found[0].get('stripPath',''))
PY
}

setup_failure_reason() {
  local path="$1"
  python3 - "$path" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception:
    print('unknown'); raise SystemExit(0)
print(str(d.get('reason') or 'unknown'))
PY
}

show_display() {
  local label="$1"
  python3 - "$STATUS" "$label" <<'PY' | tee -a "$RESULTS"
import json,sys
p,label=sys.argv[1:]
d=json.load(open(p))
for key in ('lcdUpper','lcdLower'):
    raw=str(d.get(key,'')).ljust(56)[:56]
    seg=[raw[i:i+7] for i in range(0,56,7)]
    print('%s %s=%r segments=%r' % (label,key,raw,[x.strip() for x in seg]))
PY
}

locate_instrument_mixer_column() {
  python3 - "$STATUS" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1]))
u=str(d.get('lcdUpper','')).ljust(56)[:56]
l=str(d.get('lcdLower','')).ljust(56)[:56]
us=[u[i:i+7].strip().lower() for i in range(0,56,7)]
ls=[l[i:i+7].strip().lower() for i in range(0,56,7)]
scored=[]
for i,(a,b) in enumerate(zip(us,ls)):
    score=0
    if 'studio' in a or a.startswith('studi'): score+=4
    if 'grand' in a or 'grnd' in a: score+=2
    if 'piano' in b: score+=6
    if score: scored.append((score,i,a,b))
if not scored:
    print('FAIL no-studio-piano-column upper=%r lower=%r' % (us,ls)); sys.exit(2)
scored.sort(reverse=True)
best=scored[0]
if len(scored)>1 and scored[1][0]==best[0]:
    print('FAIL ambiguous-studio-piano-column '+repr(scored)); sys.exit(3)
if best[0] < 6:
    print('FAIL low-confidence-studio-piano-column '+repr(best)); sys.exit(4)
print(best[1])
PY
}

# Prints: mode<TAB>name<TAB>token<TAB>slot<TAB>displayed-segment
find_target_parameter() {
  python3 - "$STATUS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
u=str(d.get('lcdUpper','')).ljust(56)[:56]
l=str(d.get('lcdLower','')).ljust(56)[:56]
us=[u[i:i+7].strip() for i in range(0,56,7)]
ls=[l[i:i+7].strip() for i in range(0,56,7)]
# Prefer mid-range percentage-style Studio Piano parameters seen in the native UI.
targets=[
 ('Pedal Noise','pedal'),
 ('Key Noise','key'),
 ('Release Samples','releas'),
 ('Sympathetic Resonance','sympat'),
]
def hits(segs):
    out=[]
    for name,token in targets:
        for i,s in enumerate(segs):
            n=' '.join(s.lower().split())
            if token in n:
                out.append((name,token,i,s))
    return out
lower=hits(ls); upper=hits(us)
if lower:
    name,token,i,s=lower[0]
    print('name\t%s\t%s\t%d\t%s' % (name,token,i,s)); sys.exit(0)
if upper:
    name,token,i,s=upper[0]
    print('value\t%s\t%s\t%d\t%s' % (name,token,i,s)); sys.exit(0)
sys.exit(2)
PY
}

value_at_slot() {
  local slot="$1" token="$2"
  python3 - "$STATUS" "$slot" "$token" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1])); slot=int(sys.argv[2]); token=sys.argv[3].lower()
u=str(d.get('lcdUpper','')).ljust(56)[:56]
l=str(d.get('lcdLower','')).ljust(56)[:56]
us=[u[i:i+7].strip() for i in range(0,56,7)]
ls=[l[i:i+7].strip() for i in range(0,56,7)]
if slot<0 or slot>=8 or token not in us[slot].lower(): sys.exit(2)
text=ls[slot]
m=re.search(r'[-+]?\d+(?:\.\d+)?',text.replace(',','.'))
if not m: sys.exit(3)
print(m.group(0)+'\t'+text)
PY
}

wait_value_at_slot() {
  local slot="$1" token="$2" wanted_mode="$3" baseline="${4:-}" timeout="${5:-5}"
  local start now result number text
  start=$(date +%s)
  while true; do
    if result="$(value_at_slot "$slot" "$token" 2>/dev/null)"; then
      number="${result%%$'\t'*}"
      text="${result#*$'\t'}"
      if [[ "$wanted_mode" == "any" ]]; then printf '%s\t%s\n' "$number" "$text"; return 0; fi
      if [[ "$wanted_mode" == "different" ]]; then
        python3 - "$number" "$baseline" <<'PY' >/dev/null 2>&1 && { printf '%s\t%s\n' "$number" "$text"; return 0; }
import sys,math
raise SystemExit(0 if not math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
      elif [[ "$wanted_mode" == "equal" ]]; then
        python3 - "$number" "$baseline" <<'PY' >/dev/null 2>&1 && { printf '%s\t%s\n' "$number" "$text"; return 0; }
import sys,math
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
      fi
    fi
    bridge_alive || return 2
    now=$(date +%s)
    if (( now - start >= timeout )); then return 1; fi
    sleep 0.15
  done
}

current_numeric() {
  local slot="$1" token="$2" result
  result="$(value_at_slot "$slot" "$token" 2>/dev/null)" || return 1
  printf '%s\n' "${result%%$'\t'*}"
}

progress 1 6 10 "Build and safety preflight"
if ! swift build > "$OUT/build.log" 2>&1; then
  record "RESULT=A5_FAIL reason=build"
  cat "$OUT/build.log"
  exit 20
fi
if ! "$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1; then
  record "RESULT=A5_FAIL reason=doctor"
  cat "$OUT/doctor.log"
  exit 20
fi
if ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log"; then
  record "RESULT=A5_FAIL reason=accessibility-not-trusted"
  exit 20
fi
abort_if_interrupted
progress 1 6 100 "Build and safety preflight"

progress 2 6 10 "Start previously-qualified virtual MCU control surface"
"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS" > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
for _ in $(seq 1 60); do
  bridge_alive || break
  [[ "$(json_get "$STATUS" ready)" == "true" ]] && break
  sleep 0.1
done
if [[ "$(json_get "$STATUS" ready)" != "true" ]] || ! bridge_alive; then
  record "RESULT=A5_FAIL reason=mcu-bridge-not-ready protected_parameter_state=unchanged"
  exit 20
fi
connected=0
for _ in $(seq 1 100); do
  packets="$(json_get "$STATUS" hostPacketCount)"; [[ "$packets" =~ ^[0-9]+$ ]] || packets=0
  if (( packets > 0 )); then connected=1; break; fi
  bridge_alive || break
  sleep 0.1
done
if (( ! connected )); then
  record "RESULT=A5_FAIL reason=existing-mcu-binding-not-detected protected_parameter_state=unchanged"
  exit 20
fi
capture_status "$OUT/bridge-connected.json"
progress 2 6 100 "Logic MCU traffic detected"

progress 3 6 10 "Bind exact Studio Grand / Studio Piano context"
AUTO_SETUP="$OUT/a5-auto-setup.json"
AUTO_SETUP_LOG="$OUT/a5-auto-setup.log"
"$ROOT/.build/debug/logic-a5-auto-setup" --out "$AUTO_SETUP" > "$AUTO_SETUP_LOG" 2>&1
AUTO_RC=$?
cat "$AUTO_SETUP_LOG" | tee -a "$RESULTS"
if (( AUTO_RC != 0 )); then
  AUTO_REASON="$(setup_failure_reason "$AUTO_SETUP")"
  if [[ "$AUTO_REASON" != "controls-view-not-automatable" ]]; then
    record "RESULT=A5_FAIL reason=studio-piano-context-not-resolved setup_reason=${AUTO_REASON} protected_parameter_state=unchanged"
    exit 20
  fi
  record "INFO=AX context resolved through Studio Piano window; Controls-view AX failure intentionally ignored for MCU A5"
fi
SETUP_TOPOLOGY="$OUT/setup-topology.json"
if ! capture_topology "$SETUP_TOPOLOGY" || ! track_identity_ok "$SETUP_TOPOLOGY" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=studio-grand-track-identity protected_parameter_state=unchanged"
  exit 20
fi
abort_if_interrupted
progress 3 6 100 "Studio Grand context verified; parameter path now MCU-only"

progress 4 6 10 "Enter Mackie Instrument Edit and discover Studio Piano parameter"
if ! send_display_command "PRESS INSTRUMENT" 4; then
  record "RESULT=A5_FAIL reason=mcu-instrument-mode-command protected_parameter_state=unchanged"
  exit 20
fi
show_display "instrument-mixer-1"
capture_status "$OUT/instrument-mixer-1.json"
COLUMN="$(locate_instrument_mixer_column 2>>"$RESULTS")" || {
  # Apple documents a second Instrument press as a way to switch the instrument view set.
  send_display_command "PRESS INSTRUMENT" 4 || true
  show_display "instrument-mixer-2"
  capture_status "$OUT/instrument-mixer-2.json"
  COLUMN="$(locate_instrument_mixer_column 2>>"$RESULTS")" || {
    record "RESULT=A5_FAIL reason=studio-piano-not-on-mcu-instrument-bank protected_parameter_state=unchanged"
    exit 20
  }
}
record "PASS mcu_instrument_mixer_column=${COLUMN}"
if ! send_display_command "VPOTPRESS ${COLUMN}" 4; then
  record "RESULT=A5_FAIL reason=mcu-instrument-edit-entry protected_parameter_state=unchanged"
  exit 20
fi
show_display "instrument-edit-entry"
capture_status "$OUT/instrument-edit-entry.json"

TARGET_INFO=""
TARGET_PAGE=-1
for page in $(seq 0 15); do
  capture_status "$OUT/instrument-page-${page}.json"
  show_display "instrument-page-${page}"
  if TARGET_INFO="$(find_target_parameter 2>/dev/null)"; then
    TARGET_PAGE=$page
    break
  fi
  send_display_command "PRESS RIGHT" 4 || break
done
if [[ -z "$TARGET_INFO" || "$TARGET_PAGE" -lt 0 ]]; then
  record "RESULT=A5_FAIL reason=no-known-safe-studio-piano-parameter-on-mcu-pages protected_parameter_state=unchanged"
  exit 20
fi
IFS=$'\t' read -r DISPLAY_MODE TARGET_NAME TARGET_TOKEN TARGET_SLOT TARGET_SEGMENT <<< "$TARGET_INFO"
record "PASS mcu_parameter_identity=${TARGET_NAME// /_} page=${TARGET_PAGE} slot=${TARGET_SLOT} display_mode=${DISPLAY_MODE} segment=${TARGET_SEGMENT// /_}"

# Normalize to Value display. Apple documents NAME/VALUE as switching between
# parameter-name and parameter-value formats in Instrument Edit view.
if [[ "$DISPLAY_MODE" == "name" ]]; then
  if ! send_display_command "PRESS NAMEVALUE" 4; then
    record "RESULT=A5_FAIL reason=name-value-switch protected_parameter_state=unchanged"
    exit 20
  fi
fi
BASE_RESULT="$(wait_value_at_slot "$TARGET_SLOT" "$TARGET_TOKEN" any "" 5)" || {
  record "RESULT=A5_FAIL reason=mcu-parameter-value-not-readable protected_parameter_state=unchanged"
  exit 20
}
BASELINE="${BASE_RESULT%%$'\t'*}"
BASE_TEXT="${BASE_RESULT#*$'\t'}"
record "PASS mcu_parameter_baseline name=${TARGET_NAME// /_} numeric=${BASELINE} display=${BASE_TEXT// /_}"
capture_status "$OUT/parameter-baseline.json"
abort_if_interrupted
progress 4 6 100 "Studio Piano parameter identity and baseline verified from Logic MCU feedback"

progress 5 6 10 "One MCU parameter step, Logic readback, mandatory restoration"
MUTATION_STARTED=1
# Once the first V-Pot step is sent, defer terminal interruption until the
# parameter is either independently restored or declared safety-critical.
trap '' INT TERM HUP

DIRECTION=1
if ! send_display_command "VPOT ${TARGET_SLOT} 1" 4; then
  record "RESULT=A5_SAFETY_FAIL reason=mcu-command-path-lost-after-mutation restoration=unproven"
  exit 30
fi
CHANGED_RESULT="$(wait_value_at_slot "$TARGET_SLOT" "$TARGET_TOKEN" different "$BASELINE" 5)" || true
if [[ -z "$CHANGED_RESULT" ]]; then
  # At an upper bound, +1 may legitimately do nothing. Try the opposite direction.
  DIRECTION=-1
  if ! send_display_command "VPOT ${TARGET_SLOT} -1" 4; then
    record "RESULT=A5_SAFETY_FAIL reason=mcu-command-path-lost-during-change-probe restoration=unproven"
    exit 30
  fi
  CHANGED_RESULT="$(wait_value_at_slot "$TARGET_SLOT" "$TARGET_TOKEN" different "$BASELINE" 5)" || true
fi
if [[ -z "$CHANGED_RESULT" ]]; then
  CURRENT="$(current_numeric "$TARGET_SLOT" "$TARGET_TOKEN" 2>/dev/null || true)"
  if [[ -n "$CURRENT" ]] && python3 - "$CURRENT" "$BASELINE" <<'PY' >/dev/null 2>&1
import sys,math
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  then
    RESTORATION_VERIFIED=1
    trap on_interrupt INT TERM HUP
    record "RESULT=A5_FAIL reason=mcu-vpot-write-not-observed restoration=verified"
    exit 20
  fi
  record "RESULT=A5_SAFETY_FAIL reason=changed-value-unreadable restoration=unproven"
  exit 30
fi
CHANGED="${CHANGED_RESULT%%$'\t'*}"
CHANGED_TEXT="${CHANGED_RESULT#*$'\t'}"
record "PASS mcu_parameter_changed before=${BASELINE} after=${CHANGED} display=${CHANGED_TEXT// /_}"
capture_status "$OUT/parameter-changed.json"

# Home the parameter numerically back to the exact baseline. Relative MCU
# steps are intentionally one tick at a time; direction is recomputed from
# Logic's returned value on every pass rather than assuming symmetry.
RESTORE_OK=0
for attempt in $(seq 1 12); do
  CURRENT="$(current_numeric "$TARGET_SLOT" "$TARGET_TOKEN" 2>/dev/null || true)"
  if [[ -n "$CURRENT" ]] && python3 - "$CURRENT" "$BASELINE" <<'PY' >/dev/null 2>&1
import sys,math
raise SystemExit(0 if math.isclose(float(sys.argv[1]),float(sys.argv[2]),rel_tol=0,abs_tol=1e-9) else 1)
PY
  then
    RESTORE_OK=1
    break
  fi
  STEP="$(python3 - "$CURRENT" "$BASELINE" <<'PY'
import sys
try: c=float(sys.argv[1]); b=float(sys.argv[2])
except Exception: print(''); raise SystemExit
print(-1 if c>b else 1)
PY
)"
  [[ "$STEP" == "1" || "$STEP" == "-1" ]] || break
  send_display_command "VPOT ${TARGET_SLOT} ${STEP}" 4 || break
  sleep 0.2
done
if (( ! RESTORE_OK )); then
  record "RESULT=A5_SAFETY_FAIL reason=baseline-not-restored-via-mcu restoration=unproven baseline=${BASELINE} current=${CURRENT:-unknown}"
  exit 30
fi

# Independent restoration gate: force a new Name render and a new Value render,
# then re-read the same semantic parameter from Logic's freshly emitted LCD.
if ! send_display_command "PRESS NAMEVALUE" 4; then
  record "RESULT=A5_SAFETY_FAIL reason=independent-name-render-unavailable restoration=unproven"
  exit 30
fi
NAME_CHECK="$(find_target_parameter 2>/dev/null || true)"
IFS=$'\t' read -r CHECK_MODE CHECK_NAME CHECK_TOKEN CHECK_SLOT CHECK_SEGMENT <<< "$NAME_CHECK"
if [[ "$CHECK_MODE" != "name" || "$CHECK_TOKEN" != "$TARGET_TOKEN" || "$CHECK_SLOT" != "$TARGET_SLOT" ]]; then
  record "RESULT=A5_SAFETY_FAIL reason=semantic-parameter-identity-not-reverified restoration=unproven"
  exit 30
fi
if ! send_display_command "PRESS NAMEVALUE" 4; then
  record "RESULT=A5_SAFETY_FAIL reason=independent-value-render-unavailable restoration=unproven"
  exit 30
fi
FINAL_RESULT="$(wait_value_at_slot "$TARGET_SLOT" "$TARGET_TOKEN" equal "$BASELINE" 5)" || {
  record "RESULT=A5_SAFETY_FAIL reason=fresh-mcu-baseline-readback-mismatch restoration=unproven"
  exit 30
}
RESTORATION_VERIFIED=1
trap on_interrupt INT TERM HUP
record "PASS mcu_parameter_restored baseline=${BASELINE} fresh_display=${FINAL_RESULT#*$'\t'}"
capture_status "$OUT/parameter-restored.json"
progress 5 6 100 "MCU write/readback/restore independently verified"

progress 6 6 25 "Final fixture verification and evidence packaging"
FINAL_TOPOLOGY="$OUT/final-topology.json"
if ! capture_topology "$FINAL_TOPOLOGY" || ! track_identity_ok "$FINAL_TOPOLOGY" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=track-identity-changed restoration=verified"
  exit 20
fi
abort_if_interrupted
send_command "PRESS TRACK" 3 || true
capture_status "$OUT/final-bridge-status.json"
progress 6 6 75 "Package evidence"
package_evidence
progress 6 6 100 "A5 MCU session complete"
record "RESULT=A5_PASS track=Studio_Grand plugin=Studio_Piano control_plane=virtual_MCU parameter=${TARGET_NAME// /_} before=${BASELINE} changed=${CHANGED} restored=${BASELINE} instance_identity=verified read_write_readback=verified restoration=verified"
printf '\nEvidence ZIP: %s\n' "$ZIP"
