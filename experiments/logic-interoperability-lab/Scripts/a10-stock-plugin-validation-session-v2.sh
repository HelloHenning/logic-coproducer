#!/bin/bash
set -u
ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-${TEST_ROOT}/a10-stock-plugin-${STAMP}}"
COMMANDS="${OUT}/bridge-commands.txt"; STATUS="${OUT}/bridge-status.json"; EVENTS="${OUT}/bridge-events.jsonl"; BRIDGE_LOG="${OUT}/bridge.log"; RESULTS="${OUT}/results.txt"
TARGET_TRACK="Audio 1"; SIDECHAIN_SOURCE="Studio Grand"; BRIDGE_PID=""; A10="PASS"; SIDECHAIN="FAIL"
mkdir -p "$OUT"; : > "$RESULTS"; : > "$COMMANDS"; chmod 700 "$OUT" 2>/dev/null || true; cd "$ROOT" || exit 2
record(){ printf '%s\n' "$1" | tee -a "$RESULTS"; }
cleanup(){ if [[ -n "$BRIDGE_PID" ]]&&kill -0 "$BRIDGE_PID" 2>/dev/null;then printf 'PRESS TRACK\nQUIT\n'>>"$COMMANDS" 2>/dev/null||true;sleep .2;kill "$BRIDGE_PID" 2>/dev/null||true;fi; }
trap cleanup EXIT
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
send_display(){ local c="$1" t="${2:-4}" b;b="$(json_get "$STATUS" lcdRevision)";[[ "$b" =~ ^[0-9]+$ ]]||b=0;send_command "$c" "$t"||return 1;wait_gt lcdRevision "$b" 1 >/dev/null 2>&1||true;sleep .10; }
segment(){ python3 - "$STATUS" "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
r=str(d.get(sys.argv[2],'')).ljust(56)[:56];i=int(sys.argv[3]);print(r[i*7:(i+1)*7].strip())
PY
}
find_track_column(){ python3 - "$STATUS" "$TARGET_TRACK" <<'PY'
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
ensure_plugin_mixer(){ "$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TARGET_TRACK">/dev/null 2>&1||return 1;for _ in 1 2 3;do send_display "PRESS PLUGIN" 4||return 1;if find_track_column>/dev/null 2>&1;then return 0;fi;done;return 1; }
home_insert_one(){ local col="$1";for _ in $(seq 1 18);do send_display "PRESS UP" 2||return 1;done; }
find_empty_insert(){ local col="$1" slot lower;home_insert_one "$col"||return 1;for slot in $(seq 1 15);do lower="$(segment lcdLower "$col" 2>/dev/null||true)";printf 'A10_SCAN insert_slot=%s current=%q\n' "$slot" "$lower">>"$RESULTS";if [[ "${lower// /}" == "--"||-z "$lower" ]];then printf '%s\n' "$slot";return 0;fi;((slot<15))&&send_display "PRESS DOWN" 2||true;done;return 1; }
matches_plugin(){ python3 - "$1" "$2" <<'PY'
import re,sys
s=' '.join(sys.argv[2].lower().replace('*','').split());p={'channel_eq':[r'chan.*eq',r'ch\s*eq',r'chaneq'],'compressor':[r'compr'],'distortion':[r'distor',r'^dist'],'chromaverb':[r'chroma'],'stereo_delay':[r'st.*del',r'st.*dly',r'ster.*del',r'ster.*dly',r'stdelay',r'stdly']}
raise SystemExit(0 if any(re.search(x,s) for x in p[sys.argv[1]]) else 1)
PY
}
preselect_plugin(){ local col="$1" kind="$2" max="${3:-520}" i value;for i in $(seq 1 "$max");do send_display "VPOT ${col} 1" 2||return 1;value="$(segment lcdLower "$col" 2>/dev/null||true)";if matches_plugin "$kind" "$value";then record "A10_PRESELECT kind=${kind} steps=${i} lcd=$(printf '%q' "$value")";return 0;fi;done;return 1; }
cancel_to_empty(){ local col="$1" value;for _ in $(seq 1 540);do value="$(segment lcdLower "$col" 2>/dev/null||true)";[[ "${value// /}" == "--"||-z "$value" ]]&&return 0;send_display "VPOT ${col} -1" 2||return 1;done;return 1; }
numeric_value_at(){ python3 - "$STATUS" "$1" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
i=int(sys.argv[2]);r=str(d.get('lcdLower','')).ljust(56)[:56];s=r[i*7:(i+1)*7].strip().replace(',','.');m=re.search(r'[-+]?\d+(?:\.\d+)?',s)
if not m:sys.exit(2)
print(m.group(0)+'\t'+s)
PY
}
equal_num(){ python3 - "$1" "$2" <<'PY' >/dev/null 2>&1
import math,sys
try:a=float(sys.argv[1]);b=float(sys.argv[2])
except Exception:raise SystemExit(2)
raise SystemExit(0 if math.isclose(a,b,rel_tol=0,abs_tol=1e-9) else 1)
PY
}
parameter_roundtrip(){
 local kind="$1" numeric_count names_blob slot="" baseline="" pname="" line idx candidate info changed current step final_name
 numeric_count="$(python3 - "$STATUS" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:print(0);raise SystemExit
r=str(d.get('lcdLower','')).ljust(56)[:56];print(sum(bool(re.search(r'[-+]?\d+(?:[.,]\d+)?',r[i:i+7])) for i in range(0,56,7)))
PY
)";[[ "$numeric_count" =~ ^[0-9]+$ ]]||numeric_count=0;((numeric_count>=3))&&send_display "PRESS NAMEVALUE" 3||true
 names_blob="$(python3 - "$STATUS" <<'PY'
import json,re,sys
try:d=json.load(open(sys.argv[1]))
except Exception:raise SystemExit
r=str(d.get('lcdLower','')).ljust(56)[:56]
for i in range(8):
 s=r[i*7:(i+1)*7].strip()
 if s and re.search('[A-Za-z]',s) and not any(x in s.lower() for x in ('bypass','meter')):print(str(i)+'\t'+s)
PY
)"
 [[ -n "$names_blob" ]]||{ record "A10_PARAM_FAIL kind=${kind} reason=no-semantic-names";return 1; }
 send_display "PRESS NAMEVALUE" 3||return 1
 while IFS=$'\t' read -r idx candidate;do [[ -n "$idx" ]]||continue;if info="$(numeric_value_at "$idx" 2>/dev/null)";then slot="$idx";baseline="${info%%$'\t'*}";pname="$candidate";break;fi;done <<< "$names_blob"
 [[ -n "$slot"&&-n "$baseline" ]]||{ record "A10_PARAM_FAIL kind=${kind} reason=no-semantic-numeric-parameter";return 1; }
 record "A10_PARAM kind=${kind} name=$(printf '%q' "$pname") slot=${slot} baseline=${baseline}"
 send_display "VPOT ${slot} 1" 3||return 1;sleep .12;changed="$(numeric_value_at "$slot" 2>/dev/null|cut -f1||true)"
 if [[ -z "$changed" ]]||equal_num "$changed" "$baseline";then send_display "VPOT ${slot} -1" 3||return 1;sleep .12;changed="$(numeric_value_at "$slot" 2>/dev/null|cut -f1||true)";fi
 [[ -n "$changed" ]]&&! equal_num "$changed" "$baseline"||{ record "A10_PARAM_FAIL kind=${kind} reason=no-change-observed";return 1; }
 record "A10_PARAM_CHANGED kind=${kind} before=${baseline} changed=${changed}"
 for _ in $(seq 1 24);do current="$(numeric_value_at "$slot" 2>/dev/null|cut -f1||true)";[[ -n "$current" ]]||break;equal_num "$current" "$baseline"&&break;step="$(python3 - "$current" "$baseline" <<'PY'
import sys
try:c=float(sys.argv[1]);b=float(sys.argv[2]);print(-1 if c>b else 1)
except Exception:print('')
PY
)";[[ "$step" == 1||"$step" == -1 ]]||break;send_display "VPOT ${slot} ${step}" 3||break;done
 current="$(numeric_value_at "$slot" 2>/dev/null|cut -f1||true)";[[ -n "$current" ]]&&equal_num "$current" "$baseline"||{ record "A10_PARAM_FAIL kind=${kind} reason=parameter-baseline-not-restored temporary_plugin=true";return 1; }
 send_display "PRESS NAMEVALUE" 3||return 1;final_name="$(segment lcdLower "$slot" 2>/dev/null||true)";send_display "PRESS NAMEVALUE" 3||return 1;current="$(numeric_value_at "$slot" 2>/dev/null|cut -f1||true)"
 [[ "$(printf '%s' "$final_name"|tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$pname"|tr '[:upper:]' '[:lower:]')" ]]&&equal_num "$current" "$baseline"||{ record "A10_PARAM_FAIL kind=${kind} reason=fresh-semantic-rerender-mismatch";return 1; }
 record "A10_PARAM_PASS kind=${kind} name=$(printf '%q' "$pname") before=${baseline} changed=${changed} restored=${current}";return 0
}
compare_fp(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]))
except Exception:sys.exit(2)
raise SystemExit(0 if a.get('occupiedSlots')==b.get('occupiedSlots') else 3)
PY
}
remove_current(){ local col value;ensure_plugin_mixer||return 1;col="$(find_track_column 2>/dev/null)"||return 1;for _ in $(seq 1 540);do value="$(segment lcdLower "$col" 2>/dev/null||true)";if [[ "${value// /}" == "--"||-z "$value" ]];then send_display "VPOTPRESS ${col}" 3||return 1;sleep .25;return 0;fi;send_display "VPOT ${col} -1" 2||return 1;done;return 1; }
run_effect(){
 local index="$1" kind="$2" full="$3" base="$4" col slot inserted=0 param_ok=0 side_rc=0 final
 record "A10_EFFECT_BEGIN index=${index} kind=${kind} plugin=$(printf '%q' "$full")"
 ensure_plugin_mixer||{ record "A10_EFFECT_FAIL kind=${kind} reason=plugin-mixer-not-resolved before_mutation=true";A10="FAIL";return; };col="$(find_track_column 2>/dev/null)"||{ record "A10_EFFECT_FAIL kind=${kind} reason=target-column-not-resolved before_mutation=true";A10="FAIL";return; };slot="$(find_empty_insert "$col" 2>/dev/null)"||{ record "A10_EFFECT_FAIL kind=${kind} reason=no-empty-insert before_mutation=true";A10="FAIL";return; };record "A10_EFFECT_TARGET kind=${kind} insert_slot=${slot} column=${col}"
 if ! preselect_plugin "$col" "$kind" 520;then cancel_to_empty "$col">/dev/null 2>&1||true;record "A10_EFFECT_FAIL kind=${kind} reason=stock-plugin-not-found-before-confirmation protected_chain=unchanged";A10="FAIL";return;fi
 send_display "VPOTPRESS ${col}" 4||{ record "A10_SAFETY_FAIL kind=${kind} reason=confirmation-ack-lost state=ambiguous";exit 30; };inserted=1;sleep .45
 if "$ROOT/.build/debug/logic-foundation-probe" plugin-window --name "$full" --out "$OUT/a10-${index}-${kind}-window.json">"$OUT/a10-${index}-${kind}-window.log" 2>&1;then parameter_roundtrip "$kind"&&param_ok=1||A10="FAIL";else cat "$OUT/a10-${index}-${kind}-window.log"|tee -a "$RESULTS";record "A10_EFFECT_FAIL kind=${kind} reason=inserted-instance-identity-not-verified";A10="FAIL";fi
 if [[ "$kind" == compressor ]];then
   "$ROOT/.build/debug/logic-foundation-probe" sidechain-roundtrip --plugin "$full" --source "$SIDECHAIN_SOURCE" --out "$OUT/a7-sidechain.json">"$OUT/a7-sidechain.log" 2>&1;side_rc=$?
   if((side_rc==0));then SIDECHAIN="PASS";record "A7_SIDECHAIN_RESULT=PASS plugin=Compressor source=Studio_Grand direct_restore=verified";else cat "$OUT/a7-sidechain.log"|tee -a "$RESULTS";SIDECHAIN="FAIL";record "A7_SIDECHAIN_RESULT=FAIL rc=${side_rc} temporary_compressor_cleanup_pending=true";fi
 fi
 if((inserted));then
   remove_current||{ record "A10_SAFETY_FAIL kind=${kind} reason=temporary-plugin-removal-unproven";exit 30; };final="$OUT/a10-${index}-${kind}-final-fingerprint.json";"$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$final">"$OUT/a10-${index}-${kind}-final-fingerprint.log" 2>&1||{ record "A10_SAFETY_FAIL kind=${kind} reason=final-fingerprint-unavailable";exit 30; };compare_fp "$base" "$final"||{ record "A10_SAFETY_FAIL kind=${kind} reason=chain-mismatch-after-removal";exit 30; };record "A10_EFFECT_CLEANUP=PASS kind=${kind} protected_chain=restored"
   if [[ "$kind" == compressor&&$side_rc -eq 30 ]];then record "A7_SIDECHAIN_SAFETY=RESTORED_BY_DISPOSABLE_PLUGIN_REMOVAL direct_sidechain_restore=unqualified";fi
 fi
 if((param_ok));then record "A10_EFFECT_RESULT=PASS kind=${kind}";else record "A10_EFFECT_RESULT=FAIL kind=${kind}";fi
}
record "Logic Co-Producer — A10 stock effects + A7 sidechain qualification"
swift build>"$OUT/build.log" 2>&1||{ record "RESULT=A10_FAIL reason=build";exit 20; }
"$ROOT/.build/debug/logic-lab" doctor>"$OUT/doctor.log" 2>&1||true;grep -q 'Accessibility trusted: yes' "$OUT/doctor.log"&&grep -q 'Logic Pro running: yes' "$OUT/doctor.log"||{ record "RESULT=A10_FAIL reason=doctor-or-accessibility";exit 20; }
"$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$TARGET_TRACK">"$OUT/target-track.log" 2>&1||{ record "RESULT=A10_FAIL reason=Audio-1-not-resolved";exit 20; };"$ROOT/.build/debug/logic-phase-a-probe" track-context --label "$SIDECHAIN_SOURCE">"$OUT/sidechain-source-track.log" 2>&1||{ record "RESULT=A10_FAIL reason=Studio-Grand-not-resolved";exit 20; }
BASE="$OUT/a10-baseline-fingerprint.json";"$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$BASE">"$OUT/a10-baseline-fingerprint.log" 2>&1||{ record "RESULT=A10_FAIL reason=baseline-plugin-fingerprint";exit 20; }
"$ROOT/.build/debug/logic-mcu-bridge" --commands "$COMMANDS" --status "$STATUS" --events "$EVENTS">"$BRIDGE_LOG" 2>&1&BRIDGE_PID=$!;for _ in $(seq 1 70);do bridge_alive||break;[[ "$(json_get "$STATUS" ready)" == true ]]&&break;sleep .1;done;connected=0;for _ in $(seq 1 120);do p="$(json_get "$STATUS" hostPacketCount)";[[ "$p" =~ ^[0-9]+$ ]]||p=0;if((p>0));then connected=1;break;fi;bridge_alive||break;sleep .1;done;[[ "$(json_get "$STATUS" ready)" == true&&$connected -eq 1 ]]||{ record "RESULT=A10_FAIL reason=existing-mcu-binding-not-detected";exit 20; }
run_effect 1 channel_eq "Channel EQ" "$BASE";run_effect 2 compressor "Compressor" "$BASE";run_effect 3 distortion "Distortion" "$BASE";run_effect 4 chromaverb "ChromaVerb" "$BASE";run_effect 5 stereo_delay "Stereo Delay" "$BASE"
FINAL="$OUT/a10-final-fingerprint.json";"$ROOT/.build/debug/logic-foundation-probe" plugin-fingerprint --track "$TARGET_TRACK" --out "$FINAL">"$OUT/a10-final-fingerprint.log" 2>&1||{ record "RESULT=A10_SAFETY_FAIL reason=final-fingerprint-unavailable";exit 30; };compare_fp "$BASE" "$FINAL"||{ record "RESULT=A10_SAFETY_FAIL reason=final-plugin-chain-mismatch";exit 30; }
python3 - "$OUT/a10-summary.json" "$A10" "$SIDECHAIN" <<'PY'
import json,sys
json.dump({'schema':'logic-coproducer-a10-summary/1.1','A10':sys.argv[2],'A7Sidechain':sys.argv[3],'protectedPluginChainRestored':True},open(sys.argv[1],'w'),indent=2,sort_keys=True)
PY
record "A10_GATE_SUMMARY A10=${A10} A7_SIDECHAIN=${SIDECHAIN} protected_plugin_chain=restored";[[ "$A10" == PASS ]]&&{ record "RESULT=A10_PASS stock_effect_classes=5 chain_restoration=verified";exit 0; };record "RESULT=A10_FAIL stock_effect_classes_not_all_qualified chain_restoration=verified";exit 20
