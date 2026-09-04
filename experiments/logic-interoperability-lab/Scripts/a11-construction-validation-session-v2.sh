#!/bin/bash
set -u
ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab";TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests";STAMP="$(date +%Y%m%d-%H%M%S)";OUT="${1:-${TEST_ROOT}/a11-construction-${STAMP}}";RESULTS="${OUT}/results.txt";COMMANDS="${OUT}/bridge-commands.txt";STATUS="${OUT}/bridge-status.json";EVENTS="${OUT}/bridge-events.jsonl";BRIDGE_LOG="${OUT}/bridge.log";TRACK="A11$(date +%M%S)";MUSICXML="${OUT}/${TRACK}.musicxml";BRIDGE_PID="";A11="PASS"
mkdir -p "$OUT";:>"$RESULTS";:>"$COMMANDS";chmod 700 "$OUT" 2>/dev/null||true;cd "$ROOT"||exit 2
record(){ printf '%s\n' "$1"|tee -a "$RESULTS"; }
cleanup_bridge(){ if [[ -n "$BRIDGE_PID" ]]&&kill -0 "$BRIDGE_PID" 2>/dev/null;then printf 'PRESS TRACK\nQUIT\n'>>"$COMMANDS" 2>/dev/null||true;sleep .2;kill "$BRIDGE_PID" 2>/dev/null||true;fi; }
trap cleanup_bridge EXIT
json_get(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]));v=d
except Exception:print('');raise SystemExit
for p in sys.argv[2].split('.'):v=v.get(p) if isinstance(v,dict) else None
if v is None:print('')
elif isinstance(v,bool):print('true' if v else 'false')
else:print(v)
PY
}
bridge_alive(){ [[ -n "$BRIDGE_PID" ]]&&kill -0 "$BRIDGE_PID" 2>/dev/null; }
wait_gt(){ local k="$1" b="$2" t="${3:-4}" s v;s=$(date +%s);while true;do bridge_alive||return 2;v="$(json_get "$STATUS" "$k")";if [[ "$v" =~ ^[0-9]+$ ]]&&((v>b));then return 0;fi;(( $(date +%s)-s>=t ))&&return 1;sleep .07;done; }
send_command(){ local c="$1" t="${2:-3}" b;b="$(json_get "$STATUS" commandAck)";[[ "$b" =~ ^[0-9]+$ ]]||b=0;printf '%s\n' "$c">>"$COMMANDS";wait_gt commandAck "$b" "$t"; }
send_display(){ local c="$1" t="${2:-4}" b;b="$(json_get "$STATUS" lcdRevision)";[[ "$b" =~ ^[0-9]+$ ]]||b=0;send_command "$c" "$t"||return 1;wait_gt lcdRevision "$b" 1>/dev/null 2>&1||true;sleep .10; }
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
q=''.join(sys.argv[2].lower().split());r=str(d.get('lcdUpper','')).ljust(56)[:56];h=[]
for i in range(8):
 n=''.join(r[i*7:(i+1)*7].strip().lower().split());score=20 if n==q else (10 if n and (q in n or n in q) else 0)
 if score:h.append((score,i))
if not h:sys.exit(2)
h.sort(reverse=True)
if len(h)>1 and h[0][0]==h[1][0]:sys.exit(3)
print(h[0][1])
PY
}
write_musicxml(){ cat >"$MUSICXML" <<XML
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<score-partwise version="3.1">
 <part-list><score-part id="P1"><part-name>${TRACK}</part-name></score-part></part-list>
 <part id="P1"><measure number="1">
  <attributes><divisions>1</divisions></attributes>
  <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
  <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
  <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
  <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
 </measure></part>
</score-partwise>
XML
}
capture_topology(){ "$ROOT/.build/debug/logic-mixer-matrix" topology --out "$1">"${1%.json}.log" 2>&1; }
compare_topology(){ python3 - "$1" "$2" "$TRACK" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]));tmp=sys.argv[3]
except Exception:sys.exit(2)
def c(d):
 o=[]
 for s in d.get('strips',[]):
  labels=tuple(sorted(str(x).strip() for x in s.get('labelHints',[]) if str(x).strip() and tmp not in str(x)))
  controls=[]
  for k in ('Volume','Pan','Mute','Solo'):controls.append((k,tuple(sorted(str(x.get('value','')) for x in s.get('controls',{}).get(k,[])))))
  if labels:o.append((labels,tuple(controls)))
 return sorted(o)
raise SystemExit(0 if c(a)==c(b) else 3)
PY
}
event_rows(){ python3 - "$1" <<'PY'
import json,sys
try:print(len(json.load(open(sys.argv[1])).get('rows') or []))
except Exception:print(-1)
PY
}
event_equal(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]))
except Exception:sys.exit(2)
ks=('position','status','channelDescription','channelRaw','numberDescription','numberRaw','valueDescription','valueRaw','length')
def r(d):return [{k:x.get(k) for k in ks} for x in d.get('rows',[])]
raise SystemExit(0 if r(a)==r(b) else 3)
PY
}
write_summary(){ python3 - "$OUT/a11-summary.json" "$A11" "$TRACK" <<'PY'
import json,sys
json.dump({'schema':'logic-coproducer-a11-summary/1.1','A11':sys.argv[2],'temporaryTrack':sys.argv[3],'protectedTopologyRestored':True},open(sys.argv[1],'w'),indent=2,sort_keys=True)
PY
}
record "Logic Co-Producer — A11 track/region/stock-instrument construction"
swift build>"$OUT/build.log" 2>&1||{ record "RESULT=A11_FAIL reason=build";exit 20; };"$ROOT/.build/debug/logic-lab" doctor>"$OUT/doctor.log" 2>&1||true;grep -q 'Accessibility trusted: yes' "$OUT/doctor.log"&&grep -q 'Logic Pro running: yes' "$OUT/doctor.log"||{ record "RESULT=A11_FAIL reason=doctor-or-accessibility";exit 20; }
BASE="$OUT/a11-protected-baseline-topology.json";capture_topology "$BASE"||{ record "RESULT=A11_FAIL reason=baseline-topology";exit 20; };"$ROOT/.build/debug/logic-foundation-probe" track-absent --label "$TRACK">"$OUT/a11-preflight-absent.log" 2>&1||{ record "RESULT=A11_FAIL reason=temporary-track-name-collision";exit 20; };write_musicxml
"$ROOT/.build/debug/logic-foundation-probe" import-musicxml --path "$MUSICXML">"$OUT/a11-import.log" 2>&1;import_rc=$?;cat "$OUT/a11-import.log"|tee -a "$RESULTS";if((import_rc!=0));then record "RESULT=A11_FAIL reason=MusicXML-import-not-qualified rc=${import_rc}";exit 20;fi;sleep .6
if ! "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TRACK">"$OUT/a11-created-track.log" 2>&1;then
 AFTER_IMPORT="$OUT/a11-after-unresolved-import.json";capture_topology "$AFTER_IMPORT"||{ record "RESULT=A11_SAFETY_FAIL reason=post-import-topology-unavailable";exit 30; }
 if compare_topology "$BASE" "$AFTER_IMPORT";then record "RESULT=A11_FAIL reason=MusicXML-command-returned-but-no-project-mutation-observed";exit 20;fi
 # A mutation is proven but semantic identity is not. Immediate Undo is safer than guessing a track name.
 "$ROOT/.build/debug/logic-phase-a-probe" key --name undo>"$OUT/a11-undo-unresolved-import.log" 2>&1||true;sleep .4;AFTER_UNDO="$OUT/a11-after-unresolved-import-undo.json";capture_topology "$AFTER_UNDO"||{ record "RESULT=A11_SAFETY_FAIL reason=post-undo-topology-unavailable";exit 30; };if compare_topology "$BASE" "$AFTER_UNDO";then record "RESULT=A11_FAIL reason=created-track-identity-not-resolved restoration=verified_by_immediate_undo";exit 20;fi;record "RESULT=A11_SAFETY_FAIL reason=unresolved-MusicXML-import-not-restored-by-immediate-undo";exit 30
fi
record "A11_TRACK_CREATE=PASS track=${TRACK} type=software_instrument source=MusicXML"
"$ROOT/.build/debug/logic-phase-a-probe" key --name right>"$OUT/a11-select-region.log" 2>&1||true;"$ROOT/.build/debug/logic-foundation-probe" press-menu --title "Open Event List">"$OUT/a11-open-event-list.log" 2>&1||true;sleep .3
BASE_EVENTS="$OUT/a11-region-baseline.json";"$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$BASE_EVENTS">"$OUT/a11-region-baseline.log" 2>&1||true;base_rows="$(event_rows "$BASE_EVENTS")";if [[ "$base_rows" =~ ^[0-9]+$ ]]&&((base_rows>=4));then record "A11_REGION_CREATE=PASS event_rows=${base_rows}";else A11="FAIL";record "A11_REGION_CREATE=FAIL rows=${base_rows}";fi
"$ROOT/.build/debug/logic-phase-a-probe" focus-main>"$OUT/a11-focus-main-for-double.log" 2>&1||true
if "$ROOT/.build/debug/logic-foundation-probe" press-menu --title "Double">"$OUT/a11-double-region.log" 2>&1;then sleep .35;DOUBLE="$OUT/a11-region-doubled.json";"$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$DOUBLE">"$OUT/a11-region-doubled.log" 2>&1||true;dr="$(event_rows "$DOUBLE")";if [[ "$base_rows" =~ ^[0-9]+$&&"$dr" =~ ^[0-9]+$ ]]&&((base_rows>0&&dr==base_rows*2));then record "A11_REGION_EDIT=PASS operation=Double before_rows=${base_rows} after_rows=${dr}";else A11="FAIL";record "A11_REGION_EDIT=FAIL before_rows=${base_rows} after_rows=${dr}";fi;"$ROOT/.build/debug/logic-phase-a-probe" key --name undo>"$OUT/a11-undo-double.log" 2>&1||true;sleep .35;RESTORED="$OUT/a11-region-restored.json";"$ROOT/.build/debug/logic-lab" event-list --hydrate-scroll --scroll-steps 4 --max-rows 1 --out "$RESTORED">"$OUT/a11-region-restored.log" 2>&1||true;if [[ -f "$BASE_EVENTS"&&-f "$RESTORED" ]]&&event_equal "$BASE_EVENTS" "$RESTORED";then record "A11_REGION_EDIT_RESTORE=PASS semantic_event_baseline=exact";else A11="FAIL";record "A11_REGION_EDIT_RESTORE=FAIL disposable_track_cleanup_pending=true";fi
else A11="FAIL";record "A11_REGION_EDIT=FAIL reason=Length_Double_not_resolved before_mutation=true";fi
# Stock-instrument replacement on the disposable track.
"$ROOT/.build/debug/logic-phase-a-probe" focus-main>/dev/null 2>&1||true;:>"$COMMANDS";"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS">"$BRIDGE_LOG" 2>&1&BRIDGE_PID=$!;for _ in $(seq 1 70);do bridge_alive||break;[[ "$(json_get "$STATUS" ready)" == true ]]&&break;sleep .1;done;connected=0;for _ in $(seq 1 120);do p="$(json_get "$STATUS" hostPacketCount)";[[ "$p" =~ ^[0-9]+$ ]]||p=0;if((p>0));then connected=1;break;fi;bridge_alive||break;sleep .1;done
if [[ "$(json_get "$STATUS" ready)" == true&&$connected -eq 1 ]];then "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TRACK">/dev/null 2>&1||true;col="";for _ in 1 2 3;do send_display "PRESS INSTRUMENT" 4||break;if col="$(find_column 2>/dev/null)";then break;fi;done;if [[ -n "$col" ]];then found=0;for step in $(seq 1 540);do send_display "VPOT ${col} 1" 2||break;v="$(segment lcdLower "$col" 2>/dev/null||true)";if printf '%s' "$v"|tr '[:upper:]' '[:lower:]'|grep -q 'retro';then found=1;record "A11_INSTRUMENT_PRESELECT=PASS steps=${step} lcd=$(printf '%q' "$v")";break;fi;done;if((found));then if send_display "VPOTPRESS ${col}" 4;then sleep .45;if "$ROOT/.build/debug/logic-foundation-probe" plugin-window --name "Retro Synth" --out "$OUT/a11-retro-synth-window.json">"$OUT/a11-retro-synth-window.log" 2>&1;then record "A11_INSTRUMENT_ASSIGN=PASS instrument=Retro_Synth track=${TRACK}";else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=Retro_Synth-instance-not-verified disposable_track=true";fi;else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=mcu-confirm-failed disposable_track=true";fi;else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=Retro_Synth-not-found-before-confirmation";fi;else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=temporary-track-not-on-instrument-view";fi;else A11="FAIL";record "A11_INSTRUMENT_ASSIGN=FAIL reason=existing-mcu-binding-not-detected";fi
cleanup_bridge;BRIDGE_PID=""
# Mandatory protected-project restoration: remove the entire disposable fixture.
if ! "$ROOT/.build/debug/logic-foundation-probe" delete-track --label "$TRACK">"$OUT/a11-delete-track.log" 2>&1;then cat "$OUT/a11-delete-track.log"|tee -a "$RESULTS";record "RESULT=A11_SAFETY_FAIL reason=disposable-track-removal-unproven track=${TRACK}";exit 30;fi;"$ROOT/.build/debug/logic-foundation-probe" track-absent --label "$TRACK">"$OUT/a11-final-absent.log" 2>&1||{ record "RESULT=A11_SAFETY_FAIL reason=temporary-track-still-present";exit 30; };FINAL="$OUT/a11-protected-final-topology.json";capture_topology "$FINAL"||{ record "RESULT=A11_SAFETY_FAIL reason=final-topology-unavailable";exit 30; };compare_topology "$BASE" "$FINAL"||{ record "RESULT=A11_SAFETY_FAIL reason=protected-topology-mismatch-after-cleanup";exit 30; };record "A11_CLEANUP=PASS temporary_track_removed protected_topology=restored";write_summary
if [[ "$A11" == PASS ]];then record "RESULT=A11_PASS track_region_instrument_construction=verified cleanup=verified";exit 0;fi;record "RESULT=A11_FAIL one_or_more_subgates_unqualified cleanup=verified";exit 20
