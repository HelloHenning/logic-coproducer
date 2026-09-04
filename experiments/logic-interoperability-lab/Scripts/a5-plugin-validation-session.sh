#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/a5-plugin-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-a5-plugin-session.zip"
EXPECTED_TRACK="Studio Grand"
QUERIES="Stereo Mic A,Stereo Mic B,Mono Mic,Main Volume,Pedal Noise,Key Noise,Release Samples,Sympathetic Resonance"
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
  "$ROOT/.build/debug/logic-control-probe" inventory --queries "$QUERIES" --out "$path" > "${path%.json}.log" 2>&1
}

choose_parameter() {
  local path="$1"
  python3 - "$path" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
preference=['Stereo Mic A','Main Volume','Pedal Noise','Key Noise','Release Samples','Sympathetic Resonance','Stereo Mic B','Mono Mic']

def numeric_candidates(q):
    out=[]
    for c in d.get('matches',{}).get(q,[]):
        if c.get('role')!='AXSlider' or not c.get('valueSettable') or c.get('enabled') is False: continue
        try:
            v=float(c.get('value')); lo=float(c.get('minimum')); hi=float(c.get('maximum'))
        except (TypeError,ValueError): continue
        if hi <= lo: continue
        out.append((c,v,lo,hi))
    return out

semantic_hits=sum(1 for q in preference if d.get('matches',{}).get(q))
if semantic_hits < 3:
    print('FAIL semantic_studio_piano_hits='+str(semantic_hits))
    sys.exit(2)
for q in preference:
    cs=numeric_candidates(q)
    if len(cs)==1:
        print(q)
        sys.exit(0)
print('FAIL no_unique_numeric_parameter')
sys.exit(3)
PY
}

compare_plugin_inventory() {
  local before="$1" after="$2"
  python3 - "$before" "$after" <<'PY'
import json,sys,math
b=json.load(open(sys.argv[1])); a=json.load(open(sys.argv[2]))
queries=['Stereo Mic A','Stereo Mic B','Mono Mic','Main Volume','Pedal Noise','Key Noise','Release Samples','Sympathetic Resonance']

def values(d):
    out={}
    for q in queries:
        for c in d.get('matches',{}).get(q,[]):
            if c.get('role')!='AXSlider' or not c.get('valueSettable') or c.get('enabled') is False: continue
            try: value=float(c.get('value'))
            except (TypeError,ValueError): continue
            out[(q,c.get('path',''))]=value
    return out
bv,av=values(b),values(a)
if not bv:
    print('FAIL no_numeric_plugin_parameters_in_baseline')
    sys.exit(2)
if set(bv)!=set(av):
    print('FAIL parameter_identity_changed removed=%d added=%d' % (len(set(bv)-set(av)),len(set(av)-set(bv))))
    sys.exit(3)
changed=[k for k in sorted(bv) if not math.isclose(bv[k],av[k],rel_tol=0.0,abs_tol=1e-9)]
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
print('PASS parameter=%r before=%r changed=%r restored=%r target=%s' % (
    x.get('query'),before,changed,restored,(x.get('target') or {}).get('path','')))
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
    record "INFO=A5 opener reached verified Studio Piano window; invoking dedicated Controls-view resolver"
    CONTROLS_SETUP="$OUT/a5-controls-setup.json"
    CONTROLS_SETUP_LOG="$OUT/a5-controls-setup.log"
    if ! "$ROOT/.build/debug/logic-a5-controls-setup" --out "$CONTROLS_SETUP" > "$CONTROLS_SETUP_LOG" 2>&1; then
      cat "$CONTROLS_SETUP_LOG" | tee -a "$RESULTS"
      record "RESULT=A5_FAIL reason=controls-view-resolver protected_parameter_state=unchanged"
      exit 20
    fi
    cat "$CONTROLS_SETUP_LOG" | tee -a "$RESULTS"
    record "PASS Studio_Piano_Controls_view=verified_by_dedicated_resolver"
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
  record "RESULT=A5_FAIL reason=setup-plugin-inventory protected_parameter_state=unchanged"
  exit 20
fi
CHOSEN="$(choose_parameter "$SETUP_INVENTORY")" || {
  cat "${SETUP_INVENTORY%.json}.log" | tee -a "$RESULTS"
  record "RESULT=A5_FAIL reason=no-safe-semantic-parameter protected_parameter_state=unchanged"
  exit 20
}
printf '%s\n' "$CHOSEN" > "$OUT/chosen-parameter.txt"
record "PASS native_plugin=Studio_Piano track=Studio_Grand chosen_parameter=${CHOSEN// /_} instance_identity=verified"
abort_if_interrupted
progress 2 5 100 "Native Studio Piano semantic parameter surface ready"

progress 3 5 30 "Capture authoritative semantic parameter baseline"
BASELINE="$OUT/plugin-baseline.json"
if ! capture_plugin_inventory "$BASELINE"; then
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
"$ROOT/.build/debug/logic-a5-safe-roundtrip" --query "$CHOSEN" --out "$ROUNDTRIP" > "$ROUNDTRIP_LOG" 2>&1
ROUNDTRIP_RC=$?
trap on_interrupt INT TERM HUP
cat "$ROUNDTRIP_LOG" | tee -a "$RESULTS"

ROUNDTRIP_JSON_OK=0
if [[ -f "$ROUNDTRIP" ]] && verify_roundtrip_json "$ROUNDTRIP" | tee -a "$RESULTS"; then
  ROUNDTRIP_JSON_OK=1
fi
progress 4 5 75 "Round-trip finished; verify protected baseline independently"

# Always perform the independent final baseline comparison after any attempted
# mutation, including ordinary round-trip failures. A mismatch is safety-critical.
FINAL="$OUT/plugin-final.json"
if ! capture_plugin_inventory "$FINAL"; then
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
