#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/a4-mcu-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-a4-mcu-session.zip"
COMMANDS="${OUT}/bridge-commands.txt"
STATUS="${OUT}/bridge-status.json"
EVENTS="${OUT}/bridge-events.jsonl"
BRIDGE_LOG="${OUT}/bridge.log"
RESULTS="${OUT}/results.txt"
EXPECTED_LABEL="Audio 1"
BRIDGE_PID=""
PASS=0
FAIL=0
SKIP=0

mkdir -p "$OUT"
: > "$RESULTS"

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

record() {
  printf '%s\n' "$1" | tee -a "$RESULTS"
}

cleanup() {
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    printf 'QUIT\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.2
    kill "$BRIDGE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

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
    else: print(v)
except Exception:
    print('')
PY
}

wait_status_number_gt() {
  local key="$1" before="$2" timeout="${3:-4}" start now value
  start=$(date +%s)
  while true; do
    value="$(json_get "$STATUS" "$key")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value > before )); then return 0; fi
    now=$(date +%s)
    if (( now - start >= timeout )); then return 1; fi
    sleep 0.1
  done
}

wait_command_ack() {
  local before="$1" timeout="${2:-3}"
  wait_status_number_gt commandAck "$before" "$timeout"
}

capture_topology() {
  local path="$1"
  "$ROOT/.build/debug/logic-mixer-matrix" topology --out "$path" > "${path%.json}.log" 2>&1
}

validate_target() {
  local path="$1"
  python3 - "$path" "$EXPECTED_LABEL" <<'PY'
import json,sys
p,label=sys.argv[1:]
d=json.load(open(p))
strips=[]
for s in d.get('strips',[]):
    hints=[str(x).strip() for x in s.get('labelHints',[])]
    if label in hints or any(label == h for h in hints): strips.append(s)
if len(strips)!=1:
    print(f'FAIL target_strip_count={len(strips)} expected_label={label}')
    sys.exit(2)
s=strips[0]
for kind in ('Volume','Pan','Mute','Solo'):
    cs=s.get('controls',{}).get(kind,[])
    if len(cs)!=1:
        print(f'FAIL {kind}_candidate_count={len(cs)}')
        sys.exit(3)
print('PASS strip='+s.get('stripPath','')+' label='+label)
PY
}

control_value() {
  local path="$1" kind="$2"
  python3 - "$path" "$EXPECTED_LABEL" "$kind" <<'PY'
import json,sys
p,label,kind=sys.argv[1:]
d=json.load(open(p))
ss=[s for s in d.get('strips',[]) if label in [str(x).strip() for x in s.get('labelHints',[])]]
if len(ss)!=1: sys.exit(2)
cs=ss[0].get('controls',{}).get(kind,[])
if len(cs)!=1: sys.exit(3)
print(cs[0].get('value',''))
PY
}

compare_one_change() {
  local before="$1" after="$2" kind="$3"
  python3 - "$before" "$after" "$EXPECTED_LABEL" "$kind" <<'PY'
import json,sys
bp,ap,label,kind=sys.argv[1:]
b=json.load(open(bp)); a=json.load(open(ap))
def flatten(d):
    out={}; target=None
    for s in d.get('strips',[]):
        is_target=label in [str(x).strip() for x in s.get('labelHints',[])]
        for k in ('Volume','Pan','Mute','Solo'):
            for c in s.get('controls',{}).get(k,[]):
                key=(k,c.get('path',''))
                out[key]=str(c.get('value',''))
                if is_target and k==kind: target=key
    return out,target
bs,bt=flatten(b); as_,at=flatten(a)
if bt is None or at is None or bt!=at:
    print('FAIL target-not-stable')
    sys.exit(2)
keys=set(bs)|set(as_)
changed=sorted(k for k in keys if bs.get(k)!=as_.get(k))
if changed != [bt]:
    print('FAIL changed='+repr(changed)+' expected='+repr(bt))
    sys.exit(3)
print('PASS target='+repr(bt)+' before='+bs.get(bt,'')+' after='+as_.get(bt,''))
PY
}

compare_full_restore() {
  local before="$1" after="$2"
  python3 - "$before" "$after" <<'PY'
import json,sys
b=json.load(open(sys.argv[1])); a=json.load(open(sys.argv[2]))
def flatten(d):
    out={}
    for s in d.get('strips',[]):
        for k in ('Volume','Pan','Mute','Solo'):
            for c in s.get('controls',{}).get(k,[]):
                out[(k,c.get('path',''))]=str(c.get('value',''))
    return out
bs,as_=flatten(b),flatten(a)
keys=set(bs)|set(as_)
changed=sorted(k for k in keys if bs.get(k)!=as_.get(k))
if changed:
    print('FAIL restore_changed='+repr(changed))
    sys.exit(2)
print('PASS exact_mixer_restore controls='+str(len(bs)))
PY
}

run_case() {
  local name="$1" kind="$2" command="$3" restore="$4" feedback_key="$5" idx="$6"
  local pre="${OUT}/${idx}-${name}-pre.json" post="${OUT}/${idx}-${name}-post.json" restored="${OUT}/${idx}-${name}-restored.json"
  local ack_before feedback_before case_ok=1

  progress "$idx" 8 10 "$name baseline"
  capture_topology "$pre" || { record "CASE=$name RESULT=FAIL reason=baseline-capture"; FAIL=$((FAIL+1)); return; }
  ack_before="$(json_get "$STATUS" commandAck)"; [[ "$ack_before" =~ ^[0-9]+$ ]] || ack_before=0
  feedback_before="$(json_get "$STATUS" "$feedback_key")"; [[ "$feedback_before" =~ ^[0-9]+$ ]] || feedback_before=0

  progress "$idx" 8 35 "$name controller-to-Logic"
  printf '%s\n' "$command" >> "$COMMANDS"
  wait_command_ack "$ack_before" 3 || case_ok=0
  sleep 0.5
  capture_topology "$post" || case_ok=0
  if (( case_ok )); then
    if ! compare_one_change "$pre" "$post" "$kind" | tee -a "$RESULTS"; then case_ok=0; fi
  fi

  progress "$idx" 8 60 "$name Logic-to-controller feedback"
  if ! wait_status_number_gt "$feedback_key" "$feedback_before" 3; then
    record "CASE=$name FEEDBACK=FAIL key=$feedback_key before=$feedback_before"
    case_ok=0
  else
    record "CASE=$name FEEDBACK=PASS key=$feedback_key"
  fi

  progress "$idx" 8 80 "$name restore"
  ack_before="$(json_get "$STATUS" commandAck)"; [[ "$ack_before" =~ ^[0-9]+$ ]] || ack_before=0
  printf '%s\n' "$restore" >> "$COMMANDS"
  wait_command_ack "$ack_before" 3 || case_ok=0
  sleep 0.5
  capture_topology "$restored" || case_ok=0
  if ! compare_full_restore "$pre" "$restored" | tee -a "$RESULTS"; then
    record "CRITICAL_RESTORE_FAIL case=$name"
    printf 'QUIT\n' >> "$COMMANDS"
    exit 40
  fi

  progress "$idx" 8 100 "$name complete"
  if (( case_ok )); then
    record "CASE=$name RESULT=PASS"
    PASS=$((PASS+1))
  else
    record "CASE=$name RESULT=FAIL"
    FAIL=$((FAIL+1))
  fi
}

cd "$ROOT" || exit 2
progress 1 8 5 "Build and safety preflight"
command -v python3 >/dev/null 2>&1 || { record "RESULT=FAIL reason=python3-unavailable"; exit 3; }
swift build > "$OUT/build.log" 2>&1 || { record "RESULT=FAIL reason=build"; exit 4; }
"$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || true
if ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log"; then
  record "RESULT=FAIL reason=accessibility-not-trusted"
  exit 5
fi
if ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then
  record "RESULT=FAIL reason=logic-not-running"
  exit 6
fi
progress 1 8 100 "Build and safety preflight"

progress 2 8 10 "Start virtual MCU endpoints"
: > "$COMMANDS"
"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS" > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
for _ in $(seq 1 50); do
  [[ "$(json_get "$STATUS" ready)" == "true" ]] && break
  sleep 0.1
done
if [[ "$(json_get "$STATUS" ready)" != "true" ]]; then
  record "RESULT=FAIL reason=mcu-bridge-not-ready"
  exit 7
fi
"$ROOT/.build/debug/logic-surface-explorer" midi-endpoints --out "$OUT/midi-endpoints.json" > "$OUT/midi-endpoints.log" 2>&1 || true
progress 2 8 100 "Virtual MCU endpoints ready"

progress 3 8 10 "Logic control-surface binding"
sleep 6
packets="$(json_get "$STATUS" hostPacketCount)"; [[ "$packets" =~ ^[0-9]+$ ]] || packets=0
if (( packets == 0 )); then
  cat <<'SETUP'

ONE-TIME LOGIC SETUP NEEDED
---------------------------
Keep this Terminal command running. In Logic Pro:

1. Choose Logic Pro > Control Surfaces > Setup.
2. In the Setup window choose New > Install.
3. Select "Mackie Control" and click Add.
4. Select the new Mackie Control device.
5. In Device Parameters set:
      Input Port  = CoProducer MCU To Logic
      Output Port = CoProducer MCU From Logic
6. Close the Control Surfaces Setup window.
7. Make sure the Mixer is visible in the main Logic window.
   If it is hidden, choose View > Show Mixer (or press X).

You do NOT need to return to Terminal or press Enter. The runner will detect the connection automatically.
SETUP
  osascript -e 'tell application "Logic Pro" to activate' >/dev/null 2>&1 || true
fi

connected=0
for _ in $(seq 1 1200); do
  packets="$(json_get "$STATUS" hostPacketCount)"; [[ "$packets" =~ ^[0-9]+$ ]] || packets=0
  if (( packets > 0 )); then connected=1; break; fi
  sleep 0.5
done
if (( ! connected )); then
  record "RESULT=FAIL reason=no-logic-mcu-traffic"
  exit 8
fi
progress 3 8 70 "Logic MCU traffic detected"
osascript -e 'display notification "MCU connection detected. Keep the Logic Mixer visible; the test will now run unattended." with title "Logic Co-Producer A4"' >/dev/null 2>&1 || true
sleep 2
capture_topology "$OUT/baseline.json" || { record "RESULT=FAIL reason=baseline-topology"; exit 9; }
if ! validate_target "$OUT/baseline.json" | tee -a "$RESULTS"; then
  record "RESULT=FAIL reason=expected-Audio-1-strip-not-resolved"
  exit 10
fi
progress 3 8 100 "Logic binding and target identity verified"

# Wait briefly for Logic's initial motor-fader state dump. This gives us an exact MCU raw value for restoration.
fader_raw="$(json_get "$STATUS" lastFader0Raw)"
for _ in $(seq 1 40); do
  [[ "$fader_raw" =~ ^[0-9]+$ ]] && break
  printf 'HANDSHAKE\n' >> "$COMMANDS"
  sleep 0.25
  fader_raw="$(json_get "$STATUS" lastFader0Raw)"
done

if [[ "$fader_raw" =~ ^[0-9]+$ ]]; then
  if (( fader_raw <= 8191 )); then fader_test=$((fader_raw + 512)); else fader_test=$((fader_raw - 512)); fi
  run_case "volume" "Volume" "FADER 0 $fader_test" "FADER 0 $fader_raw" "fader0Counter" 4
else
  progress 4 8 100 "volume skipped: no host fader baseline"
  record "CASE=volume RESULT=SKIP reason=no-host-fader-baseline"
  SKIP=$((SKIP+1))
fi

pan_before="$(control_value "$OUT/baseline.json" Pan 2>/dev/null || true)"
if [[ "$pan_before" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  pan_int="${pan_before%%.*}"
  if (( pan_int < 127 )); then pan_delta=1; else pan_delta=-1; fi
  run_case "pan" "Pan" "PAN 0 $pan_delta" "PAN 0 $((-pan_delta))" "ring0Counter" 5
else
  progress 5 8 100 "pan skipped: baseline unreadable"
  record "CASE=pan RESULT=SKIP reason=baseline-unreadable"
  SKIP=$((SKIP+1))
fi

run_case "mute" "Mute" "BUTTON MUTE 0" "BUTTON MUTE 0" "mute0Counter" 6
run_case "solo" "Solo" "BUTTON SOLO 0" "BUTTON SOLO 0" "solo0Counter" 7

progress 8 8 20 "Final independent restoration verification"
capture_topology "$OUT/final.json" || { record "RESULT=FAIL reason=final-topology"; exit 41; }
if ! compare_full_restore "$OUT/baseline.json" "$OUT/final.json" | tee -a "$RESULTS"; then
  record "RESULT=CRITICAL_FAIL reason=final-mixer-state-differs"
  exit 42
fi
printf 'QUIT\n' >> "$COMMANDS"
sleep 0.4
progress 8 8 70 "Package evidence"
rm -f "$ZIP"
(
  cd "$TEST_ROOT" || exit 1
  /usr/bin/zip -qr "$ZIP" "$(basename "$OUT")"
) || { record "RESULT=FAIL reason=zip"; exit 43; }
progress 8 8 100 "A4 session complete"

record "SUMMARY PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
if (( FAIL == 0 && SKIP == 0 && PASS == 4 )); then
  record "RESULT=A4_PASS representative_strip=Audio_1 controls=volume,pan,mute,solo restoration=verified"
  printf '\nEvidence ZIP: %s\n' "$ZIP"
  exit 0
fi
record "RESULT=A4_INCOMPLETE"
printf '\nEvidence ZIP: %s\n' "$ZIP"
exit 20
