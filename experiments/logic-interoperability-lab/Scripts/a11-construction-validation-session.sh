#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-${TEST_ROOT}/a11-construction-${STAMP}}"
RESULTS="${OUT}/results.txt"
COMMANDS="${OUT}/bridge-commands.txt"
STATUS="${OUT}/bridge-status.json"
EVENTS="${OUT}/bridge-events.jsonl"
BRIDGE_LOG="${OUT}/bridge.log"
TRACK="A11$(date +%M%S)"
MUSICXML="${OUT}/${TRACK}.musicxml"
BRIDGE_PID=""
IMPORTED=0
A11="PASS"

mkdir -p "$OUT"
: > "$RESULTS"
: > "$COMMANDS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2
record(){ printf '%s\n' "$1" | tee -a "$RESULTS"; }

cleanup_bridge(){
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    printf 'PRESS TRACK\nQUIT\n' >> "$COMMANDS" 2>/dev/null || true
    sleep 0.2
    kill "$BRIDGE_PID" 2>/dev/null || true
  fi
}
trap cleanup_bridge EXIT

json_get(){
  python3 - "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]));v=d
except Exception:print('');raise SystemExit
for p in sys.argv[2].split('.'):v=v.get(p) if isinstance(v,dict) else None
if v is None:print('')
elif isinstance(v,bool):print('true' if v else 'false')
else:print(v)
PY
}
bridge_alive(){ [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; }
wait_gt(){ local k="$1" b="$2" t="${3:-4}" s v;s=$(date +%s);while true;do bridge_alive||return 2;v="$(json_get "$STATUS" "$k")";if [[ "$v" =~ ^[0-9]+$ ]]&&((v>b));then return 0;fi;(( $(date +%s)-s>=t ))&&return 1;sleep 0.08;done; }
send_command(){ local c="$1" t="${2:-3}" b;b="$(json_get "$STATUS" commandAck)";[[ "$b" =~ ^[0-9]+$ ]]||b=0;printf '%s\n' "$c">>"$COMMANDS";wait_gt commandAck "$b" "$t"; }
send_display(){ local c="$1" t="${2:-4}" b;b="$(json_get "$STATUS" lcdRevision)";[[ "$b" =~ ^[0-9]+$ ]]||b=0;send_command "$c" "$t"||return 1;wait_gt lcdRevision "$b" 1 >/dev/null 2>&1||true;sleep 0.12; }
segment(){ python3 - "$STATUS" "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
r=str(d.get(sys.argv[2],'')).ljust(56)[:56];i=int(sys.argv[3]);print(r[i*7:(i+1)*7].strip())
PY
}
find_column(){ python3 - "$STATUS" "$TRACK" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
q=''.join(sys.argv[2].lower().split());r=str(d.get('lcdUpper','')).ljust(56)[:56];s=[r[i:i+7].strip() for i in range(0,56,7)];h=[]
for i,x in enumerate(s):
 n=''.join(x.lower().split())
 if n==q:h.append((20,i))
 elif q in n or n in q:h.append((10,i))
if not h:sys.exit(2)
h.sort(reverse=True)
if len(h)>1 and h[0][0]==h[1][0]:sys.exit(3)
print(h[0][1])
PY
}

write_musicxml(){
cat > "$MUSICXML" <<XML
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>${TRACK}</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
  </measure></part>
</score-partwise>
XML
}

capture_topology(){ "$ROOT/.build/debug/logic-mixer-matrix" topology --out "$1" > "${1%.json}.log" 2>&1; }
compare_protected_topology(){
python3 - "$1" "$2" "$TRACK" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]));tmp=sys.argv[3]
except Exception:sys.exit(2)
def canon(d):
 out=[]
 for s in d.get('strips',[]):
  labels=tuple(sorted(str(x).strip() for x in s.get('labelHints',[]) if str(x).strip() and tmp not in str(x)))
  controls=[]
  for k in ('Volume','Pan','Mute','Solo'):
   vals=tuple(sorted(str(c.get('value','')) for c in s.get('controls',{}).get(k,[])))
   controls.append((k,vals))
  if labels:out.append((labels,tuple(controls)))
 return sorted(out)
raise SystemExit(0 if canon(a)==canon(b) else 3)
PY
}

event_rows(){
python3 - "$1" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]));print(len(d.get('rows') or []))
except Exception:print(-1)
PY
}
event_semantic_equal(){
python3 - "$1" "$2" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]))
except Exception:sys.exit(2)
def rows(d):
 return [{k:r.get(k) for k in ('position','status','channelDescription','channelRaw','numberDescription','numberRaw','valueDescription','valueRaw','length')} for r in d.get('rows',[])]
raise SystemExit(0 if rows(a)==rows(b) else 3)
PY
}

record "Logic Co-Producer — A11 track/region/stock-instrument construction"
if ! swift build > "$OUT/build.log" 2>&1; then record "RESULT=A11_FAIL reason=build"; exit 20; fi
if ! "$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log" || ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then record "RESULT=A11_FAIL reason=doctor-or-accessibility"; exit 20; fi
BASE="$OUT/a11-protected-baseline-topology.json"
capture_topology "$BASE" || { record "RESULT=A11_FAIL reason=baseline-topology"; exit 20; }
if ! "$ROOT/.build/debug/logic-foundation-probe" track-absent --label "$TRACK" > "$OUT/a11-preflight-absent.log" 2>&1; then record "RESULT=A11_FAIL reason=temporary-track-name-collision"; exit 20; fi
write_musicxml

if ! "$ROOT/.build/debug/logic-foundation-probe" import-musicxml --path "$MUSICXML" > "$OUT/a11-import.log" 2>&1; then
  cat "$OUT/a11-import.log" | tee -a "$RESULTS"
  record "A11_RESULT=FAIL reason=musicxml-import-command-not-qualified before_mutation_or_state_unproven"
  exit 20
fi
IMPORTED=1
sleep 0.6
if ! "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TRACK" > "$OUT/a11-created-track.log" 2>&1; then
  record "A11_SAFETY_FAIL reason=musicxml-import-returned-success-but-created-track-not-resolved cleanup_required=true"
  # We cannot safely name-target deletion if the imported track cannot be resolved.
  exit 30
fi
record "A11_TRACK_CREATE=PASS track=${TRACK} type=software_instrument source=MusicXML"

# Select the imported MIDI region using Logic's documented/default next-region action.
"$ROOT/.build/debug/logic-phase-a-probe" key --name right > "$OUT/a11-select-region.log" 2>&1 || true
"$ROOT/.build/debug/logic-foundation-probe" press-menu --title "Open Event List" > "$OUT/a11-open-event-list.log" 2>&1 || true
sleep 0.3
BASE_EVENTS="$OUT/a11-region-baseline.json"
"$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$BASE_EVENTS" > "$OUT/a11-region-baseline.log" 2>&1 || true
base_rows="$(event_rows "$BASE_EVENTS")"
if [[ "$base_rows" =~ ^[0-9]+$ ]] && (( base_rows >= 4 )); then
  record "A11_REGION_CREATE=PASS event_rows=${base_rows}"
else
  A11="FAIL"; record "A11_REGION_CREATE=FAIL reason=created-region-event-list-not-qualified rows=${base_rows}"
fi

# On the disposable region only, exercise a structurally distinct resize/content-repeat operation.
"$ROOT/.build/debug/logic-phase-a-probe" focus-main > "$OUT/a11-focus-main-for-double.log" 2>&1 || true
if "$ROOT/.build/debug/logic-foundation-probe" press-menu --title "Double" > "$OUT/a11-double-region.log" 2>&1; then
  sleep 0.35
  DOUBLE_EVENTS="$OUT/a11-region-doubled.json"
  "$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$DOUBLE_EVENTS" > "$OUT/a11-region-doubled.log" 2>&1 || true
  doubled_rows="$(event_rows "$DOUBLE_EVENTS")"
  if [[ "$base_rows" =~ ^[0-9]+$ && "$doubled_rows" =~ ^[0-9]+$ ]] && (( base_rows > 0 && doubled_rows == base_rows * 2 )); then
    record "A11_REGION_EDIT=PASS operation=Double before_rows=${base_rows} after_rows=${doubled_rows}"
  else
    A11="FAIL"; record "A11_REGION_EDIT=FAIL reason=doubled-region-readback-mismatch before_rows=${base_rows} after_rows=${doubled_rows}"
  fi
  "$ROOT/.build/debug/logic-phase-a-probe" key --name undo > "$OUT/a11-undo-double.log" 2>&1 || true
  sleep 0.35
  RESTORED_EVENTS="$OUT/a11-region-restored.json"
  "$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$RESTORED_EVENTS" > "$OUT/a11-region-restored.log" 2>&1 || true
  if [[ -f "$BASE_EVENTS" && -f "$RESTORED_EVENTS" ]] && event_semantic_equal "$BASE_EVENTS" "$RESTORED_EVENTS"; then
    record "A11_REGION_EDIT_RESTORE=PASS exact_semantic_event_baseline=true"
  else
    # The entire track remains disposable and will be deleted, so this is a gate failure,
    # not a protected-project safety failure unless final track deletion/topology fails.
    A11="FAIL"; record "A11_REGION_EDIT_RESTORE=FAIL disposable_track_cleanup_will_restore_protected_project=true"
  fi
else
  A11="FAIL"; record "A11_REGION_EDIT=FAIL reason=Edit_Length_Double_not_semantically_resolved before_mutation=true"
fi

# Instrument assignment on the disposable track via the previously qualified MCU plane.
"$ROOT/.build/debug/logic-phase-a-probe" focus-main >/dev/null 2>&1 || true
: > "$COMMANDS"
"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS" > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
for _ in $(seq 1 70);do bridge_alive||break;[[ "$(json_get "$STATUS" ready)" == "true" ]]&&break;sleep 0.1;done
connected=0
for _ in $(seq 1 120);do p="$(json_get "$STATUS" hostPacketCount)";[[ "$p" =~ ^[0-9]+$ ]]||p=0;if((p>0));then connected=1;break;fi;bridge_alive||break;sleep 0.1;done
if [[ "$(json_get "$STATUS" ready)" == "true" && "$connected" == "1" ]]; then
  "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TRACK" >/dev/null 2>&1 || true
  found_col=""
  for _ in 1 2 3;do send_display "PRESS INSTRUMENT" 4||break;if found_col="$(find_column 2>/dev/null)";then break;fi;done
  if [[ -n "$found_col" ]]; then
    found_retro=0
    for step in $(seq 1 520);do
      send_display "VPOT ${found_col} 1" 2||break
      v="$(segment lcdLower "$found_col" 2>/dev/null||true)"
      if printf '%s' "$v" | tr '[:upper:]' '[:lower:]' | grep -q 'retro';then found_retro=1;record "A11_INSTRUMENT_PRESELECT=PASS steps=${step} lcd=$(printf '%q' "$v")";break;fi
    done
    if((found_retro));then
      if send_display "VPOTPRESS ${found_col}" 4;then
        sleep 0.45
        if "$ROOT/.build/debug/logic-foundation-probe" plugin-window --name "Retro Synth" --out "$OUT/a11-retro-synth-window.json" > "$OUT/a11-retro-synth-window.log" 2>&1;then
          record "A11_INSTRUMENT_ASSIGN=PASS instrument=Retro_Synth track=${TRACK}"
        else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=Retro_Synth_instance_not_verified disposable_track=true";fi
      else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=mcu_confirm_failed disposable_track=true";fi
    else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=Retro_Synth_not_found_before_confirmation protected_existing_project=unchanged";fi
  else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=imported_track_not_on_mcu_instrument_view";fi
else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=existing_mcu_binding_not_detected";fi
cleanup_bridge
BRIDGE_PID=""

# Mandatory cleanup of the entire disposable track is the protected-state gate.
if ! "$ROOT/.build/debug/logic-foundation-probe" delete-track --label "$TRACK" > "$OUT/a11-delete-track.log" 2>&1; then
  cat "$OUT/a11-delete-track.log" | tee -a "$RESULTS"
  record "RESULT=A11_SAFETY_FAIL reason=disposable-track-removal-unproven track=${TRACK}"
  exit 30
fi
IMPORTED=0
if ! "$ROOT/.build/debug/logic-foundation-probe" track-absent --label "$TRACK" > "$OUT/a11-final-absent.log" 2>&1; then record "RESULT=A11_SAFETY_FAIL reason=temporary-track-still-present";exit 30;fi
FINAL="$OUT/a11-protected-final-topology.json"
capture_topology "$FINAL" || { record "RESULT=A11_SAFETY_FAIL reason=final-topology-unavailable";exit 30; }
if ! compare_protected_topology "$BASE" "$FINAL"; then record "RESULT=A11_SAFETY_FAIL reason=protected-topology-mismatch-after-disposable-track-removal";exit 30;fi
record "A11_CLEANUP=PASS temporary_track_removed protected_topology=restored"
python3 - "$OUT/a11-summary.json" "$A11" "$TRACK" <<'PY'
import json,sys
json.dump({'schema':'logic-coproducer-a11-summary/1.0','A11':sys.argv[2],'temporaryTrack':sys.argv[3],'protectedTopologyRestored':True},open(sys.argv[1],'w'),indent=2,sort_keys=True)
PY
if [[ "$A11" == "PASS" ]];then record "RESULT=A11_PASS track_region_instrument_construction=verified cleanup=verified";exit 0;fi
record "RESULT=A11_FAIL one_or_more_construction_subgates_unqualified cleanup=verified"
exit 20
