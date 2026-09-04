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

mkdir -p "$OUT"
: > "$RESULTS"
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
trap package_evidence EXIT INT TERM

capture_topology() {
  local path="$1"
  "$ROOT/.build/debug/logic-mixer-matrix" topology --out "$path" > "${path%.json}.log" 2>&1
}

selected_track_ok() {
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
if int(found[0].get('selectedDescendantCount',0)) < 1: sys.exit(4)
print('PASS selected_track='+label+' strip='+found[0].get('stripPath',''))
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

setup_ready() {
  local topo="$1" inv="$2"
  capture_topology "$topo" || return 1
  selected_track_ok "$topo" >/dev/null 2>&1 || return 1
  capture_plugin_inventory "$inv" || return 1
  choose_parameter "$inv" >/dev/null 2>&1 || return 1
  return 0
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
progress 1 5 100 "Build and safety preflight"

progress 2 5 5 "Studio Grand / Studio Piano setup detection"
SETUP_TOPOLOGY="$OUT/setup-topology.json"
SETUP_INVENTORY="$OUT/setup-plugin-inventory.json"
if ! setup_ready "$SETUP_TOPOLOGY" "$SETUP_INVENTORY"; then
  cat <<'TXT'

ONE-TIME LOGIC SETUP NEEDED
---------------------------
Keep this Terminal command running. In the same synthetic Logic project:

1. Make sure the Mixer is visible (press X if needed).
2. Select the track named "Studio Grand".
3. On that channel strip, click the software-instrument slot to open its Studio Piano plug-in.
4. In the plug-in window's View pop-up, choose "Controls".
5. Close any other plug-in windows, leaving Studio Piano open.

Do not change any plug-in parameter yourself.
You do NOT need to return to Terminal or press Enter. The runner will detect the setup automatically.
TXT

  start="$(date +%s)"
  while ! setup_ready "$SETUP_TOPOLOGY" "$SETUP_INVENTORY"; do
    now="$(date +%s)"
    if (( now - start >= 300 )); then
      record "RESULT=A5_FAIL reason=setup-timeout"
      exit 20
    fi
    sleep 2
  done
fi
selected_track_ok "$SETUP_TOPOLOGY" | tee -a "$RESULTS"
CHOSEN="$(choose_parameter "$SETUP_INVENTORY")" || {
  record "RESULT=A5_FAIL reason=no-safe-semantic-parameter"
  exit 20
}
printf '%s\n' "$CHOSEN" > "$OUT/chosen-parameter.txt"
record "PASS native_plugin=Studio_Piano track=Studio_Grand chosen_parameter=${CHOSEN// /_}"
progress 2 5 100 "Native Studio Piano semantic parameter surface ready"

progress 3 5 30 "Capture authoritative semantic parameter baseline"
BASELINE="$OUT/plugin-baseline.json"
if ! capture_plugin_inventory "$BASELINE"; then
  record "RESULT=A5_FAIL reason=baseline-inventory"
  exit 20
fi
BASE_CHOSEN="$(choose_parameter "$BASELINE")" || {
  record "RESULT=A5_FAIL reason=baseline-parameter-resolution"
  exit 20
}
if [[ "$BASE_CHOSEN" != "$CHOSEN" ]]; then
  record "RESULT=A5_FAIL reason=parameter-identity-not-deterministic"
  exit 20
fi
progress 3 5 100 "Authoritative semantic baseline captured"

progress 4 5 25 "One parameter write with fresh independent readback"
ROUNDTRIP="$OUT/plugin-roundtrip.json"
if ! "$ROOT/.build/debug/logic-control-probe" numeric-roundtrip --query "$CHOSEN" --out "$ROUNDTRIP" > "$OUT/plugin-roundtrip.log" 2>&1; then
  cat "$OUT/plugin-roundtrip.log" | tee -a "$RESULTS"
  record "RESULT=A5_FAIL reason=parameter-roundtrip"
  exit 20
fi
cat "$OUT/plugin-roundtrip.log" | tee -a "$RESULTS"
python3 - "$ROUNDTRIP" <<'PY' | tee -a "$RESULTS"
import json,sys
x=json.load(open(sys.argv[1]))
if x.get('result')!='PASS':
    print('FAIL roundtrip_json_result='+str(x.get('result')))
    sys.exit(2)
print('PASS parameter=%r before=%r changed=%r restored=%r target=%s' % (
    x.get('query'),x.get('before'),x.get('changed'),x.get('restored'),(x.get('target') or {}).get('path','')))
PY
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  record "RESULT=A5_FAIL reason=roundtrip-json-verification"
  exit 20
fi
progress 4 5 100 "Semantic parameter round-trip verified"

progress 5 5 25 "Independent final restoration verification"
FINAL="$OUT/plugin-final.json"
if ! capture_plugin_inventory "$FINAL"; then
  record "RESULT=A5_FAIL reason=final-inventory"
  exit 20
fi
if ! compare_plugin_inventory "$BASELINE" "$FINAL" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=final-restore-mismatch"
  exit 20
fi
FINAL_TOPOLOGY="$OUT/final-topology.json"
if ! capture_topology "$FINAL_TOPOLOGY" || ! selected_track_ok "$FINAL_TOPOLOGY" | tee -a "$RESULTS"; then
  record "RESULT=A5_FAIL reason=track-identity-changed"
  exit 20
fi
progress 5 5 75 "Package evidence"
package_evidence
progress 5 5 100 "A5 session complete"
record "RESULT=A5_PASS track=Studio_Grand plugin=Studio_Piano parameter=${CHOSEN// /_} read_write_readback=verified restoration=verified"
printf '\nEvidence ZIP: %s\n' "$ZIP"
