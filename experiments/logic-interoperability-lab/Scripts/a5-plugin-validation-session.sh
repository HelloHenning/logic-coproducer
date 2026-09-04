#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/a5-plugin-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-a5-plugin-session.zip"
EXPECTED_TRACK="Studio Grand"
RESULTS="${OUT}/results.txt"
INTERRUPTED=0

mkdir -p "$OUT"
: > "$RESULTS"
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

on_interrupt() {
  INTERRUPTED=1
  record "NOTICE=interrupt-requested will-stop-at-safe-checkpoint"
}

trap package_evidence EXIT
trap on_interrupt INT TERM HUP

abort_if_interrupted() {
  if (( INTERRUPTED )); then
    record "RESULT=A5_FAIL reason=interrupted-before-mutation protected_state=unchanged"
    exit 130
  fi
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
if len(found)!=1: sys.exit(3)
print('PASS track_identity='+label+' strip='+found[0].get('stripPath',''))
PY
}

capture_plugin_inventory() {
  local path="$1"
  "$ROOT/.build/debug/logic-a5-plugin-probe" inventory --out "$path" > "${path%.json}.log" 2>&1
}

choose_parameter() {
  local path="$1"
  python3 - "$path" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
preference=['Stereo Mic A','Main Volume','Pedal Noise','Key Noise','Release Samples','Sympathetic Resonance','Stereo Mic B','Mono Mic']
if d.get('result')!='PASS':
    print('FAIL inventory_result='+str(d.get('result'))+' reason='+str(d.get('reason')))
    sys.exit(2)
semantic=d.get('semanticParameterHits') or []
params=d.get('parameters') or []
if len(semantic)<3 or len(params)<3:
    print('FAIL semantic_hits=%d mapped_parameters=%d' % (len(semantic),len(params)))
    sys.exit(2)
by_name={p.get('name'):p for p in params if p.get('name')}
for name in preference:
    p=by_name.get(name)
    if not p: continue
    slider=p.get('slider') or {}
    if not slider.get('valueSettable'): continue
    try:
        value=float(p.get('value'))
    except (TypeError,ValueError):
        continue
    lo=p.get('minimum'); hi=p.get('maximum')
    if lo is not None and hi is not None:
        try:
            if float(hi)<=float(lo): continue
        except (TypeError,ValueError):
            continue
    if int(p.get('score') or 0)<70: continue
    print(name)
    sys.exit(0)
print('FAIL no_unique_semantic_slider_binding')
sys.exit(3)
PY
}

compare_plugin_inventory() {
  local before="$1" after="$2"
  python3 - "$before" "$after" <<'PY'
import json,sys,math
b=json.load(open(sys.argv[1])); a=json.load(open(sys.argv[2]))
if b.get('result')!='PASS' or a.get('result')!='PASS':
    print('FAIL inventory_result before=%r after=%r' % (b.get('result'),a.get('result')))
    sys.exit(2)

def values(d):
    out={}
    for p in d.get('parameters') or []:
        name=p.get('name')
        if not name: continue
        try: value=float(p.get('value'))
        except (TypeError,ValueError): continue
        out[name]=value
    return out
bv,av=values(b),values(a)
if len(bv)<3:
    print('FAIL insufficient_mapped_plugin_parameters_in_baseline='+str(len(bv)))
    sys.exit(2)
if set(bv)!=set(av):
    print('FAIL semantic_parameter_identity_changed removed=%r added=%r' % (sorted(set(bv)-set(av)),sorted(set(av)-set(bv))))
    sys.exit(3)
changed=[name for name in sorted(bv) if not math.isclose(bv[name],av[name],rel_tol=0.0,abs_tol=1e-9)]
if changed:
    print('FAIL final_parameter_changes='+repr(changed))
    sys.exit(4)
print('PASS exact_plugin_restore semantic_parameters='+str(len(bv)))
PY
}

verify_roundtrip_json() {
  local path="$1"
  python3 - "$path" <<'PY'
import json,sys,math
x=json.load(open(sys.argv[1]))
if x.get('result')!='PASS':
    print('FAIL roundtrip_json_result='+str(x.get('result'))+' reason='+str(x.get('reason')))
    sys.exit(2)
if x.get('restorationVerified') is not True:
    print('FAIL roundtrip_restoration_not_verified')
    sys.exit(3)
before=x.get('before'); changed=x.get('changed'); restored=x.get('restored')
if before is None or changed is None or restored is None:
    print('FAIL roundtrip_missing_values')
    sys.exit(4)
if math.isclose(float(before),float(changed),rel_tol=0.0,abs_tol=1e-9):
    print('FAIL roundtrip_change_not_observed')
    sys.exit(5)
if not math.isclose(float(before),float(restored),rel_tol=0.0,abs_tol=1e-6):
    print('FAIL roundtrip_restore_value_mismatch')
    sys.exit(6)
target=x.get('target') or {}
slider=target.get('slider') or {}
print('PASS parameter=%r before=%r changed=%r restored=%r target=%s association=%s' % (
    x.get('query'),before,changed,restored,slider.get('path',''),target.get('association','')))
PY
}

setup_failure_reason() {
  local path="$1"
  python3 - "$path" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    print('unknown')
    raise SystemExit(0)
print(str(d.get('reason') or 'unknown'))
PY
}

progress 1 5 10 "Build and safety preflight"
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
abort_if_interrupted
progress 1 5 100 "Build and safety preflight"

progress 2 5 10 "Automatically prepare Studio Grand / Studio Piano UI"
AUTO_SETUP="$OUT/a5-auto-setup.json"
AUTO_SETUP_LOG="$OUT/a5-auto-setup.log"
"$ROOT/.build/debug/logic-a5-auto-setup" --out "$AUTO_SETUP" > "$AUTO_SETUP_LOG" 2>&1
AUTO_SETUP_RC=$?
cat "$AUTO_SETUP_LOG" | tee -a "$RESULTS"

if (( AUTO_SETUP_RC != 0 )); then
  AUTO_REASON="$(setup_failure_reason "$AUTO_SETUP")"
  if [[ "$AUTO_REASON" == "controls-view-not-automatable" ]]; then
    record "INFO=A5 opener reached verified Studio Piano window; semantic plug-in probe will own Controls mapping"
  else
    record "RESULT=A5_FAIL reason=automatic-plugin-ui-setup protected_parameter_state=unchanged setup_reason=${AUTO_REASON}"
    exit 20
  fi
fi

SETUP_TOPOLOGY="$OUT/setup-topology.json"
if ! capture_topology "$SETUP_TOPOLOGY" || ! track_identity_ok "$SETUP_TOPOLOGY" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=studio-grand-track-identity protected_parameter_state=unchanged"
  exit 20
fi
SETUP_INVENTORY="$OUT/setup-plugin-inventory.json"
if ! capture_plugin_inventory "$SETUP_INVENTORY"; then
  cat "${SETUP_INVENTORY%.json}.log" | tee -a "$RESULTS"
  record "RESULT=A5_FAIL reason=setup-plugin-inventory protected_parameter_state=unchanged"
  exit 20
fi
cat "${SETUP_INVENTORY%.json}.log" | tee -a "$RESULTS"
CHOSEN="$(choose_parameter "$SETUP_INVENTORY")" || {
  record "RESULT=A5_FAIL reason=no-safe-semantic-parameter protected_parameter_state=unchanged"
  exit 20
}
printf '%s\n' "$CHOSEN" > "$OUT/chosen-parameter.txt"
record "PASS native_plugin=Studio_Piano track=Studio_Grand chosen_parameter=${CHOSEN// /_} instance_identity=verified semantic_slider_mapping=verified"
abort_if_interrupted
progress 2 5 100 "Native Studio Piano semantic parameter surface ready"

progress 3 5 30 "Capture authoritative semantic parameter baseline"
BASELINE="$OUT/plugin-baseline.json"
if ! capture_plugin_inventory "$BASELINE"; then
  cat "${BASELINE%.json}.log" | tee -a "$RESULTS"
  record "RESULT=A5_FAIL reason=baseline-inventory protected_parameter_state=unchanged"
  exit 20
fi
BASE_CHOSEN="$(choose_parameter "$BASELINE")" || {
  record "RESULT=A5_FAIL reason=baseline-parameter-resolution protected_parameter_state=unchanged"
  exit 20
}
if [[ "$BASE_CHOSEN" != "$CHOSEN" ]]; then
  record "RESULT=A5_FAIL reason=parameter-identity-not-deterministic protected_parameter_state=unchanged"
  exit 20
fi
abort_if_interrupted
progress 3 5 100 "Authoritative semantic baseline captured"

progress 4 5 20 "One parameter write, independent readback, mandatory restore"
ROUNDTRIP="$OUT/plugin-roundtrip.json"
ROUNDTRIP_LOG="$OUT/plugin-roundtrip.log"

# The intentional mutation is a tiny protected critical section. Ignore terminal
# interruption signals in this child so Ctrl-C/TERM/HUP cannot strand the value
# between the write and the binary's verified restoration attempt.
trap '' INT TERM HUP
"$ROOT/.build/debug/logic-a5-plugin-probe" roundtrip --query "$CHOSEN" --out "$ROUNDTRIP" > "$ROUNDTRIP_LOG" 2>&1
ROUNDTRIP_RC=$?
trap on_interrupt INT TERM HUP
cat "$ROUNDTRIP_LOG" | tee -a "$RESULTS"

ROUNDTRIP_JSON_OK=0
if [[ -f "$ROUNDTRIP" ]] && verify_roundtrip_json "$ROUNDTRIP" | tee -a "$RESULTS"; then
  ROUNDTRIP_JSON_OK=1
fi
progress 4 5 75 "Round-trip finished; verify protected baseline independently"

# Always perform the independent final semantic inventory comparison after any
# attempted mutation. A mismatch is safety-critical and stops the session.
FINAL="$OUT/plugin-final.json"
if ! capture_plugin_inventory "$FINAL"; then
  cat "${FINAL%.json}.log" | tee -a "$RESULTS"
  record "RESULT=A5_SAFETY_FAIL reason=final-inventory-unavailable restoration=unproven"
  exit 30
fi
if ! compare_plugin_inventory "$BASELINE" "$FINAL" | tee -a "$RESULTS"; then
  record "RESULT=A5_SAFETY_FAIL reason=final-restore-mismatch restoration=unproven"
  exit 30
fi
record "PASS protected_plugin_baseline=independently_verified"
progress 4 5 100 "Protected Studio Piano baseline independently restored"

progress 5 5 30 "Verify fixture identity and package evidence"
FINAL_TOPOLOGY="$OUT/final-topology.json"
if ! capture_topology "$FINAL_TOPOLOGY" || ! track_identity_ok "$FINAL_TOPOLOGY" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=track-identity-changed restoration=verified"
  exit 20
fi

if (( INTERRUPTED )); then
  record "RESULT=A5_FAIL reason=interrupted-after-safe-restoration restoration=verified"
  exit 130
fi

if (( ROUNDTRIP_RC != 0 || ROUNDTRIP_JSON_OK != 1 )); then
  record "RESULT=A5_FAIL reason=parameter-roundtrip restoration=verified roundtrip_exit=${ROUNDTRIP_RC}"
  exit 20
fi

progress 5 5 75 "Package evidence"
package_evidence
progress 5 5 100 "A5 session complete"
record "RESULT=A5_PASS track=Studio_Grand plugin=Studio_Piano parameter=${CHOSEN// /_} instance_identity=verified read_write_readback=verified restoration=verified"
printf '\nEvidence ZIP: %s\n' "$ZIP"
